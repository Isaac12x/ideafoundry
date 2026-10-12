require "json"
require "tmpdir"

module Kb
  # Hidden transcript for a downloaded video: yt-dlp pulls the English subtitles
  # (json3, or VTT/SRT from other sites), chunked into ~90s "MM:SS - text" lines.
  module VideoTranscript
    MAX_CHUNK_SECONDS = 90
    # Exact codes only: "en.*" also matches YouTube's auto-translated tracks (en-ar,
    # en-bg, ...), one request each, which trips HTTP 429 and fails the run.
    SUB_LANGS = "en,en-US,en-GB,en-orig".freeze
    OTHER_SUB_LANGS = "en.*,eng.*,en".freeze # the 429 problem is YouTube-specific
    FORMATS = %w[json3 vtt srt].freeze # preference order
    TIMING = /((?:\d+:)?\d+:\d+[.,]\d+)\s*-->\s*((?:\d+:)?\d+:\d+[.,]\d+)/

    class Error < StandardError; end
    class NotInstalled < Error; end

    # => [video_id, transcript or nil]. nil = yt-dlp ran fine but no English subs.
    # Raises Error when yt-dlp itself fails (caller retries).
    def self.fetch(url)
      bin = KbDownloadJob.yt_dlp_bin or raise NotInstalled, "yt-dlp is not installed."
      Dir.mktmpdir("kb-transcript") do |dir|
        out, status = KbDownloadJob.capture([ bin, "--no-playlist", "--no-simulate", "--skip-download", "--write-subs", "--write-auto-subs",
                                             "--sub-langs", KbDownloadJob.youtube?(url) ? SUB_LANGS : OTHER_SUB_LANGS,
                                             "--sub-format", "json3/vtt/srt/best",
                                             "-o", File.join(dir, "%(id)s.%(ext)s"), "--print", "id", KbDownloadJob.media_url(url) ])
        files = Dir[File.join(dir, "*")].select { |f| FORMATS.include?(File.extname(f).delete(".")) }
        # A failed side-track (e.g. 429 on one language) still exits non-zero; keep what landed.
        raise Error, "yt-dlp could not fetch subtitles for #{url}." unless status&.success? || files.any?

        # Best format first, then the plain "en" track over en-orig / en-US variants.
        file = files.min_by { |f| ext = File.extname(f); [ FORMATS.index(ext.delete(".")), File.basename(f).end_with?(".en#{ext}") ? 0 : 1, f ] }
        [ out.to_s.lines.last.to_s.strip.presence, (file && render(File.read(file), File.extname(file).delete("."))) ]
      end
    end

    # subtitle string -> "MM:SS - text\n..." or nil when empty.
    def self.render(content, ext = "json3")
      text = format(chunk(ext == "json3" ? parse(content) : parse_cues(content)))
      text.presence
    end

    # VTT / SRT. Rolling auto-captions repeat the previous cue's last line; drop those.
    def self.parse_cues(content)
      prev = []
      content.to_s.split(/\r?\n(?:[[:blank:]]*\r?\n)+/).filter_map do |block|
        lines = block.lines.map(&:chomp)
        i = lines.index { |l| l.match?(TIMING) } or next
        from, to = lines[i].match(TIMING).captures.map { |t| seconds(t) }
        cur = lines[(i + 1)..].map { |l| CGI.unescapeHTML(l.gsub(/<[^>]*>/, "")).squish }.reject(&:empty?)
        fresh = cur - prev
        prev = cur
        { start: from, duration: to - from, text: fresh.join(" ") } if fresh.any?
      end
    end

    def self.seconds(stamp) = stamp.tr(",", ".").split(":").map(&:to_f).inject(0) { |sum, part| sum * 60 + part }

    def self.parse(json3)
      Array(JSON.parse(json3)["events"]).filter_map do |ev|
        next unless ev["segs"]
        text = ev["segs"].map { |s| s["utf8"] }.join.squish
        next if text.empty?
        { start: ev["tStartMs"].to_i / 1000.0, duration: ev["dDurationMs"].to_i / 1000.0, text: text }
      end
    end

    def self.chunk(entries)
      chunks = []
      cur = nil
      dur = 0
      entries.each do |e|
        if cur && dur + e[:duration] <= MAX_CHUNK_SECONDS
          cur[:text] += " #{e[:text]}"
          dur += e[:duration]
        else
          chunks << cur if cur
          cur = { start: e[:start], text: e[:text] }
          dur = e[:duration]
        end
      end
      chunks << cur if cur
      chunks
    end

    def self.format(chunks)
      chunks.map { |c| m, s = c[:start].divmod(60); "%02d:%02d - %s\n" % [ m, s, c[:text] ] }.join
    end
  end
end
