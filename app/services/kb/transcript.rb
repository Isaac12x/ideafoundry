require "fileutils"
require "open3"
require "tmpdir"

module Kb
  # Selectable, time-coded transcript for KB audio/video. Source of truth is a
  # sidecar "<name>.vtt" next to the media: it works for files dropped straight
  # into the KB (no kb_downloads row), shows in the tree/Finder, and is picked up
  # by players as captions. Local whisper writes it; downloaded captions
  # (kb_downloads.transcript, "MM:SS - text") are the fallback source.
  module Transcript
    LOCK_TTL = 6.hours # long media on CPU whisper
    LINE = /\A(\d+):(\d{2}) - (.*)\z/
    class Error < StandardError; end

    module_function

    def bin = LocalTool.path("whisper", env: "WHISPER_BIN")

    def available? = bin.present?

    def model = ENV["WHISPER_MODEL"].presence || "base"

    def state_dir = Rails.env.test? ? Rails.root.join("tmp", "kb_transcripts_test_#{Process.pid}") : Rails.root.join("storage", "kb_transcripts")

    def sidecar(abs) = abs.sub(/#{Regexp.escape(File.extname(abs))}\z/, ".vtt")

    # Sidecar path when `abs` is media with a captions file next to it, else nil.
    def sidecar_for(abs)
      side = sidecar(abs)
      side if media?(abs) && File.file?(side)
    end

    def media?(abs) = %i[video audio].include?(MediaTypes.kind_for(abs))

    # => [{ start:, end:, text: }] seconds; sidecar first, then downloaded captions.
    def cues(abs, download = nil)
      return from_vtt(File.read(sidecar(abs))) if File.file?(sidecar(abs))

      from_captions(download&.transcript)
    end

    def from_vtt(content)
      VideoTranscript.parse_cues(content).map { |cue| { start: cue[:start], end: cue[:start] + cue[:duration], text: cue[:text] } }
    end

    # "MM:SS - text" lines (90s chunks): each cue ends where the next begins.
    def from_captions(text)
      rows = text.to_s.lines.filter_map do |line|
        m = line.chomp.match(LINE) and { start: m[1].to_i * 60 + m[2].to_i, text: m[3] }
      end
      rows.each_with_index.map { |row, i| row.merge(end: rows[i + 1]&.fetch(:start) || row[:start] + VideoTranscript::MAX_CHUNK_SECONDS) }
    end

    # true when the caller now owns the run (one job per file).
    def claim!(abs)
      FileUtils.mkdir_p(state_dir)
      lock = state_file(abs, "lock")
      FileUtils.rm_f(lock) if File.file?(lock) && File.mtime(lock) < LOCK_TTL.ago
      FileUtils.rm_f(state_file(abs, "err"))
      File.open(lock, File::WRONLY | File::CREAT | File::EXCL) { true }
    rescue Errno::EEXIST
      false
    end

    def running?(abs) = File.file?(state_file(abs, "lock")) && File.mtime(state_file(abs, "lock")) > LOCK_TTL.ago

    def error(abs) = (File.read(state_file(abs, "err")) if File.file?(state_file(abs, "err")))

    def state_file(abs, ext) = state_dir.join("#{Digest::SHA256.hexdigest(abs)}.#{ext}")

    # Runs whisper into a temp dir, then moves the VTT beside the media. Returns the sidecar path.
    def transcribe!(abs)
      raise Error, "whisper is not installed." unless available?

      Dir.mktmpdir("kb-whisper") do |dir|
        _out, err, status = Subprocess.capture(bin, abs, "--model", model, "--output_format", "vtt", "--output_dir", dir, "--fp16", "False", "--verbose", "False", timeout: timeout_for(abs))
        vtt = File.join(dir, "#{File.basename(abs, '.*')}.vtt")
        raise Error, err.to_s.lines.last.to_s.strip.presence || "whisper failed." unless status.success? && File.size?(vtt)

        target = sidecar(abs)
        FileUtils.cp(vtt, "#{target}.tmp")
        File.rename("#{target}.tmp", target)
        target
      end
    rescue Subprocess::Timeout => e
      raise Error, "Transcription timed out (#{e.message})."
    ensure
      FileUtils.rm_f(state_file(abs, "lock"))
    end

    # 3x the media duration + 60s (ffprobe); unknown duration gets the lock TTL.
    def timeout_for(abs)
      out, _err, status = Subprocess.capture("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", abs, timeout: 30)
      seconds = out.to_f
      status.success? && seconds.positive? ? seconds * 3 + 60 : LOCK_TTL.to_i
    rescue Subprocess::Timeout, SystemCallError
      LOCK_TTL.to_i
    end
  end
end
