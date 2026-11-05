require "open-uri"
require "open3"

# Downloads a URL into a KB folder. YouTube -> yt-dlp with the mp3/mp4 preset;
# article pages (Wikipedia, Grokipedia, blogs...) -> reader-mode PDF; other
# media sites -> yt-dlp then a plain HTTP fallback; direct file links -> HTTP
# straight away. Output is confined to the target source's directory.
class KbDownloadJob < ApplicationJob
  queue_as :default

  # Paywalled page with no archived copy yet: ask the Wayback Machine to take
  # one, then come back for it.
  ARCHIVE_RETRIES = 3
  ARCHIVE_WAIT = 5.minutes

  YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be].freeze
  # yt-dlp's page scrapers, not real video sites (HTML5MediaEmbed matches any article with an <audio>).
  NOT_SITE_EXTRACTORS = %w[Generic HTML5MediaEmbed].freeze
  # Extensions we fetch directly instead of routing through yt-dlp.
  DIRECT_EXTS = %w[
    .pdf .md .html .htm .docx .xlsx .csv .txt .json .zip
    .png .jpg .jpeg .webp .gif .tif .tiff
    .mp3 .wav .ogg .m4a .aac .flac .mp4 .webm .mov .ogv
  ].freeze

  def perform(download_id)
    dl = KbDownload.find_by(id: download_id)
    return if dl.nil? || dl.status != "pending"

    base = base_path_for(dl)
    return fail!(dl, "KB source is not available.") if base.nil?

    target = resolve_dir(base, dl.dir)
    return fail!(dl, "Target folder not found.") if target.nil?

    case Kb::ProjectLock.write_block(base, dl.dir)
    when :busy # locking/unlocking right now: try again shortly
      return self.class.set(wait: 30.seconds).perform_later(dl.id)
    when :locked
      return fail!(dl, "Project is locked. Unlock it, then retry.")
    end

    dl.update!(status: "running")

    path = fetch(dl, target)
    return if dl.failed? || path == :retry

    unless path && File.exist?(path) && File.expand_path(path).start_with?("#{base}/")
      return fail!(dl, "Download produced no file.")
    end

    # ponytail: yt-dlp and cut_clip (direct media) cut clips; articles come whole, so don't claim a clip.
    dl.assign_attributes(clip_start: nil, clip_end: nil) unless @clipped
    save_note(dl, path)
    dl.update!(status: "done", filename: File.basename(path), error: nil)
    dl.queue_transcript
  rescue => e
    Rails.logger.error("KbDownloadJob #{download_id}: #{e.class}: #{e.message}")
    fail!(dl, e.message) if dl
  end

  private

  # "Why are you saving this?" -> the file's .note.md sidecar. The sidecar is the source of truth, so the row's copy goes.
  def save_note(dl, path)
    return if dl.note.blank?

    Kb::Note.write!(path, dl.note) if Kb::Note.eligible?(path)
    dl.note = nil
  rescue SystemCallError, ArgumentError => e
    Rails.logger.warn("KbDownloadJob #{dl.id}: note not saved: #{e.message}")
  end

  def fetch(dl, dir)
    if direct_file?(dl.url)
      http_download(dl, dir)
    elsif youtube?(dl.url)
      yt_dlp(dl, dir) || fail!(dl, "yt-dlp could not download #{dl.url}.")
    elsif %w[video audio].include?(dl.format)
      yt_dlp(dl, dir) || http_download(dl, dir)
    else
      # A page yt-dlp has a real extractor for is a video, not an article.
      if dl.format == "auto" && (kind = self.class.video_kind(dl.url))
        saved = yt_dlp(dl, dir, kind)
        return saved if saved
      end
      page = reader_pdf(dl, dir)
      return page if page || dl.failed?
      return http_download(dl, dir) if dl.format == "page"
      yt_dlp(dl, dir) || http_download(dl, dir)
    end
  end

  # Path of the saved reader PDF, :retry while waiting on an archive, or nil
  # when the URL isn't an article (caller falls back to media/raw download).
  def reader_pdf(dl, dir)
    page = Kb::WebPage.fetch(dl.url)
    return nil unless page
    if page.paywalled?
      page = archived_page(dl)
      return wait_for_archive(dl) unless page
    end
    return nil unless page.article? || dl.format == "page"

    dl.title = page.title
    if dl.references_state.nil? && page.references.any?
      dl.assign_attributes(reference_list: page.references, references_state: "offered")
    end

    html = page.reader_html(source: dl.url)
    dest = unique_path(File.join(dir, "#{KbDownload.safe_name(page.title)}.pdf"))
    return dest if Kb::ReaderPdf.write(html, dest)

    # ponytail: no headless Chrome on this machine -> keep the reader HTML.
    dest = unique_path(dest.delete_suffix(".pdf") + ".html")
    File.write(dest, html)
    dest
  end

  def archived_page(dl)
    Kb::WebPage.archive_candidates(dl.url, dl.archive_url).each do |candidate|
      page = Kb::WebPage.fetch(candidate)
      return page if page && !page.paywalled? && page.article?
    rescue StandardError => e
      Rails.logger.info("KbDownloadJob archive miss #{candidate}: #{e.message}")
    end
    nil
  end

  def wait_for_archive(dl)
    return fail!(dl, "Paywalled, and no archived copy was found.") if dl.attempts >= ARCHIVE_RETRIES

    Kb::WebPage.request_archive(dl.url) if dl.attempts.zero?
    dl.update!(status: "pending", attempts: dl.attempts + 1, error: "Paywalled — waiting for an archived copy.")
    self.class.set(wait: ARCHIVE_WAIT).perform_later(dl.id)
    :retry
  end

  # :video / :audio when yt-dlp has a site-specific (non-generic) extractor for
  # the URL, or it's a bare HLS/DASH manifest; nil for articles and unknown pages.
  def self.video_kind(url)
    bin = yt_dlp_bin or return nil
    return :video if %w[.m3u8 .mpd].include?(File.extname(URI.parse(url).path.to_s).downcase)

    out, status = capture([ bin, "--no-playlist", "--simulate", "--print", "extractor_key", "--print", "vcodec", media_url(url) ])
    key, vcodec = out.to_s.lines.map(&:strip).first(2)
    return nil unless status&.success? && key.present? && !NOT_SITE_EXTRACTORS.include?(key)
    vcodec == "none" ? :audio : :video
  rescue URI::InvalidURIError
    nil
  end

  # Vimeo's page extractor demands a login now; the embed player URL does not.
  def self.media_url(url)
    m = url.match(%r{\Ahttps?://(?:www\.)?vimeo\.com/(?:[^/?#]+/)*?(\d+)(?:/([0-9a-f]+))?/?(?:[?#].*)?\z}i)
    m ? "https://player.vimeo.com/video/#{m[1]}#{"?h=#{m[2]}" if m[2]}" : url
  end

  def yt_dlp(dl, dir, kind = nil)
    bin = yt_dlp_bin
    return fail!(dl, "yt-dlp is not installed.") if bin.nil?

    out, status = capture(self.class.yt_dlp_args(bin, dl, dir, kind))
    return nil unless status&.success?
    @clipped = dl.clip?
    out.to_s.lines.map(&:strip).reject(&:empty?).last
  end

  # Clips (a start and/or end) go through --download-sections, cut on keyframe
  # boundaries re-encoded so the cut is exact, and are named in the file.
  def self.yt_dlp_args(bin, dl, dir, kind = nil)
    name = "%(title)s"
    if dl.clip?
      from = Kb::ClipTime.slug(dl.clip_start || 0)
      name += " [clip #{dl.clip_end ? "#{from}-#{Kb::ClipTime.slug(dl.clip_end)}" : "from #{from}"}]"
    end
    args = [ bin, "--no-playlist", "--no-overwrites", "--no-simulate",
            "--print", "after_move:filepath", "-P", dir, "-o", "#{name}.%(ext)s" ]
    args += [ "--download-sections", Kb::ClipTime.section(dl.clip_start, dl.clip_end), "--force-keyframes-at-cuts" ] if dl.clip?
    case dl.format
    when "audio" then args += [ "-t", "mp3" ]
    when "video" then args += [ "-t", "mp4" ]
    when "auto"
      args += [ "-t", "mp4" ] if youtube?(dl.url)
      # ponytail: merge only, no remux -- some sites (archive.org .ogv) can't convert to mp4.
      args += [ "--merge-output-format", "mp4" ] if kind == :video
    end
    args << media_url(dl.url)
  end

  def http_download(dl, dir)
    dest = unique_path(File.join(dir, filename_from_url(dl.url)))
    # open-uri follows same-scheme redirects; https->http is refused (good).
    URI.parse(dl.url).open("rb") do |io|
      File.open(dest, "wb") { |f| IO.copy_stream(io, f) }
    end
    dl.clip? && Kb::MediaTypes.kind_for(dest).in?(%i[video audio]) ? cut_clip(dl, dest) : dest
  rescue OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED, RuntimeError => e
    fail!(dl, "Download failed: #{e.message}")
    nil
  end

  # Accurate (decoded, re-encoded) cut of a downloaded media file to the clip,
  # named like yt-dlp's clips. The whole download is dropped once the cut lands;
  # a failed cut fails the job rather than silently keeping the full file.
  def cut_clip(dl, path)
    ext = File.extname(path)
    from = dl.clip_start || 0
    span = dl.clip_end ? [ "-t", (dl.clip_end - from).to_s ] : []
    suffix = dl.clip_end ? "#{Kb::ClipTime.slug(from)}-#{Kb::ClipTime.slug(dl.clip_end)}" : "from #{Kb::ClipTime.slug(from)}"
    dest = unique_path(File.join(File.dirname(path), "#{File.basename(path, ext)} [clip #{suffix}]#{ext}"))
    table = Kb::MediaTypes.kind_for(path) == :audio ? Kb::MediaEditProcessor::AUDIO_CODECS : Kb::MediaEditProcessor::VIDEO_CODECS
    codecs = table.fetch(ext.downcase, [])
    _out, err, status = Open3.capture3("ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", path,
                                       "-ss", from.to_s, *span, "-map_metadata", "0", *codecs, dest)
    unless status.success? && File.size?(dest)
      FileUtils.rm_f(dest)
      fail!(dl, "Could not cut the clip: #{err.to_s.lines.last.to_s.strip.presence || 'ffmpeg failed'}")
      return nil
    end
    FileUtils.rm_f(path)
    @clipped = true
    dest
  rescue Errno::ENOENT
    fail!(dl, "Could not cut the clip: ffmpeg is not installed.")
    nil
  end

  def base_path_for(dl)
    sources = KbSource.list(dl.user)
    src = if dl.source_path.present?
      sources.find { |source| File.expand_path(source[:path]) == File.expand_path(dl.source_path) }
    else
      sources[dl.source_index]
    end
    return nil unless src

    base = File.expand_path(src[:path])
    FileUtils.mkdir_p(base) if src[:native] && !Dir.exist?(base)
    Dir.exist?(base) ? base : nil
  end

  def resolve_dir(base, rel)
    return base if rel.blank?
    abs = File.expand_path(File.join(base, rel))
    return nil unless abs.start_with?("#{base}/") || abs == base
    File.directory?(abs) ? abs : nil
  end

  def self.youtube?(url)
    host = URI.parse(url).host.to_s.downcase
    YOUTUBE_HOSTS.include?(host)
  rescue URI::InvalidURIError
    false
  end

  def youtube?(url) = self.class.youtube?(url)

  def self.direct_file?(url)
    path = URI.parse(url).path.to_s
    # A wiki "File:x.webm" page is HTML, not the file.
    DIRECT_EXTS.include?(File.extname(path).downcase) && !path.include?("/wiki/")
  rescue URI::InvalidURIError
    false
  end

  def direct_file?(url) = self.class.direct_file?(url)

  def filename_from_url(url)
    raw = CGI.unescape(File.basename(URI.parse(url).path.to_s))
    raw = raw.gsub(%r{[/\\\0]}, "_").sub(/\A\.+/, "")
    raw.presence || "download"
  end

  def unique_path(path)
    return path unless File.exist?(path)
    dir  = File.dirname(path)
    ext  = File.extname(path)
    stem = File.basename(path, ext)
    i = 1
    i += 1 while File.exist?(File.join(dir, "#{stem}-#{i}#{ext}"))
    File.join(dir, "#{stem}-#{i}#{ext}")
  end

  # Shared with Kb::VideoTranscript.
  def self.capture(args)
    out, err, status = Open3.capture3(*args)
    Rails.logger.info("yt-dlp: #{err}") unless status.success?
    [ out, status ]
  rescue Errno::ENOENT
    [ nil, nil ]
  end

  def self.yt_dlp_bin
    [ ENV["YT_DLP_BIN"], File.expand_path("~/.local/bin/yt-dlp"), "yt-dlp" ].compact.find do |cand|
      cand == "yt-dlp" ? system("which", "yt-dlp", out: File::NULL, err: File::NULL) : File.executable?(cand)
    end
  end

  def capture(args) = self.class.capture(args)

  def yt_dlp_bin = self.class.yt_dlp_bin

  def fail!(dl, message)
    dl&.update!(status: "failed", error: message.to_s)
    nil
  end
end
