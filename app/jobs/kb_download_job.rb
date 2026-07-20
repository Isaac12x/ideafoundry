require "open-uri"
require "open3"

# Downloads a URL into a KB folder. YouTube -> yt-dlp with the mp3/mp4 preset;
# other media sites -> yt-dlp then a plain HTTP fallback; direct file links ->
# HTTP straight away. Output is confined to the target source's directory.
class KbDownloadJob < ApplicationJob
  queue_as :default

  YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be].freeze
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

    dl.update!(status: "running")

    path = fetch(dl, target)
    return if dl.failed?

    unless path && File.exist?(path) && File.expand_path(path).start_with?("#{base}/")
      return fail!(dl, "Download produced no file.")
    end

    dl.update!(status: "done", filename: File.basename(path))
  rescue => e
    Rails.logger.error("KbDownloadJob #{download_id}: #{e.class}: #{e.message}")
    fail!(dl, e.message) if dl
  end

  private

  def fetch(dl, dir)
    if direct_file?(dl.url)
      http_download(dl, dir)
    elsif youtube?(dl.url)
      yt_dlp(dl, dir) || fail!(dl, "yt-dlp could not download #{dl.url}.")
    else
      yt_dlp(dl, dir) || http_download(dl, dir)
    end
  end

  def yt_dlp(dl, dir)
    bin = yt_dlp_bin
    return fail!(dl, "yt-dlp is not installed.") if bin.nil?

    args = [bin, "--no-playlist", "--no-overwrites", "--no-simulate",
            "--print", "after_move:filepath", "-P", dir, "-o", "%(title)s.%(ext)s"]
    case dl.format
    when "audio" then args += ["-t", "mp3"]
    when "video" then args += ["-t", "mp4"]
    when "auto"  then args += ["-t", "mp4"] if youtube?(dl.url)
    end
    args << dl.url

    out, status = capture(args)
    return nil unless status&.success?
    out.to_s.lines.map(&:strip).reject(&:empty?).last
  end

  def http_download(dl, dir)
    dest = unique_path(File.join(dir, filename_from_url(dl.url)))
    # open-uri follows same-scheme redirects; https->http is refused (good).
    URI.parse(dl.url).open("rb") do |io|
      File.open(dest, "wb") { |f| IO.copy_stream(io, f) }
    end
    dest
  rescue OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED, RuntimeError => e
    fail!(dl, "Download failed: #{e.message}")
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

  def youtube?(url)
    host = URI.parse(url).host.to_s.downcase
    YOUTUBE_HOSTS.include?(host)
  rescue URI::InvalidURIError
    false
  end

  def direct_file?(url)
    ext = File.extname(URI.parse(url).path.to_s).downcase
    DIRECT_EXTS.include?(ext)
  rescue URI::InvalidURIError
    false
  end

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

  def capture(args)
    out, err, status = Open3.capture3(*args)
    Rails.logger.info("yt-dlp: #{err}") unless status.success?
    [out, status]
  rescue Errno::ENOENT
    [nil, nil]
  end

  def yt_dlp_bin
    [ENV["YT_DLP_BIN"], File.expand_path("~/.local/bin/yt-dlp"), "yt-dlp"].compact.find do |cand|
      cand == "yt-dlp" ? system("which", "yt-dlp", out: File::NULL, err: File::NULL) : File.executable?(cand)
    end
  end

  def fail!(dl, message)
    dl&.update!(status: "failed", error: message.to_s)
    nil
  end
end
