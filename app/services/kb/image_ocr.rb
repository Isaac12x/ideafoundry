require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

module Kb
  # Selectable text for KB images ("Live Text"): local tesseract, line boxes in
  # percent of the image. Everything stays on this machine. Results are cached
  # OUTSIDE the KB (storage/kb_ocr, keyed by path + mtime + size) -- except for
  # private projects, which callers run with cache: false so no OCR text of a
  # private/locked project ever lands in app storage.
  module ImageOcr
    MIN_CONFIDENCE = 30
    LOCK_TTL = 10.minutes
    TIMEOUT = 20 # seconds per tesseract/ffmpeg call
    MAX_AGE = 30.days
    MAX_ENTRIES = 2000
    class Error < StandardError; end

    module_function

    def cache_dir = Rails.env.test? ? Rails.root.join("tmp", "kb_ocr_test_#{Process.pid}") : Rails.root.join("storage", "kb_ocr")

    def bin = LocalTool.path("tesseract", env: "TESSERACT_BIN")

    def available? = bin.present?

    def key(abs) = Digest::SHA256.hexdigest([ abs, File.mtime(abs).to_f, File.size(abs) ].join("\0"))

    def cached(abs)
      file = cache_dir.join("#{key(abs)}.json")
      JSON.parse(File.read(file), symbolize_names: true).except(:path) if File.file?(file)
    end

    # true when the caller now owns the run (enqueue exactly one job per image).
    def claim!(abs)
      FileUtils.mkdir_p(cache_dir)
      lock = cache_dir.join("#{key(abs)}.lock")
      FileUtils.rm_f(lock) if File.file?(lock) && File.mtime(lock) < LOCK_TTL.ago
      File.open(lock, File::WRONLY | File::CREAT | File::EXCL) { true }
    rescue Errno::EEXIST
      false
    end

    # => { width:, height:, lines: [{ text:, x:, y:, w:, h: }], text: }
    def run!(abs, cache: true)
      lock = cache_dir.join("#{key(abs)}.lock")
      result = parse(tsv(abs))
      # A project that started locking meanwhile must not get a fresh entry.
      if cache && !Kb::ProjectLock.busy_path?(abs)
        FileUtils.mkdir_p(cache_dir)
        file = cache_dir.join("#{key(abs)}.json")
        # path lets Derived.purge_ocr find (and drop) a locked project's entries.
        File.write("#{file}.tmp", JSON.generate(result.merge(path: abs)))
        File.rename("#{file}.tmp", file)
        evict!
      end
      result
    ensure
      FileUtils.rm_f(lock) if lock
    end

    # ponytail: lazy eviction on write, oldest first; a cron isn't worth it for a cache.
    def evict!
      entries = Dir.glob(cache_dir.join("*.json")).sort_by { |f| File.mtime(f) }
      stale = entries.select { |f| File.mtime(f) < MAX_AGE.ago }
      stale |= entries.first([ entries.size - MAX_ENTRIES, 0 ].max)
      FileUtils.rm_f(stale)
    end

    # Drops every cached entry for a file under dir (by recorded path, and by key for
    # entries written before the path was recorded). Call while the files still exist.
    def purge!(dir)
      prefix = "#{File.expand_path(dir)}/"
      Dir.glob(cache_dir.join("*.json")).each do |f|
        FileUtils.rm_f(f) if JSON.parse(File.read(f))["path"].to_s.start_with?(prefix)
      rescue JSON::ParserError, SystemCallError
        nil
      end
      Dir.glob(File.join(dir, "**", "*")).each do |f|
        next unless File.file?(f) && !File.symlink?(f) && Kb::MediaTypes.kind_for(f) == :image

        FileUtils.rm_f([ cache_dir.join("#{key(f)}.json"), cache_dir.join("#{key(f)}.lock") ])
      end
    end

    def tsv(abs)
      raise Error, "tesseract is not installed." unless available?

      tsv!(abs)
    rescue Subprocess::Timeout
      raise Error, "Reading text timed out."
    end

    def tsv!(abs)
      out, err, status = Subprocess.capture(bin, abs, "stdout", "tsv", timeout: TIMEOUT)
      return out if status.success?

      # Leptonica can't read every webp build; transcode through ffmpeg once.
      via_png(abs) || raise(Error, err.to_s.lines.last.to_s.strip.presence || "tesseract failed.")
    end

    def via_png(abs)
      Dir.mktmpdir("kb-ocr") do |dir|
        png = File.join(dir, "in.png")
        _o, _e, decoded = Subprocess.capture("ffmpeg", "-y", "-loglevel", "error", "-i", abs, png, timeout: TIMEOUT)
        next unless decoded.success?

        out, _err, status = Subprocess.capture(bin, png, "stdout", "tsv", timeout: TIMEOUT)
        out if status.success?
      end
    rescue Errno::ENOENT
      nil
    end

    # tesseract TSV: level page block par line word left top width height conf text
    def parse(tsv)
      rows = tsv.lines.drop(1).map { |line| line.chomp.split("\t", 12) }
      page = rows.find { |row| row[0] == "1" }
      width = page&.at(8).to_f
      height = page&.at(9).to_f
      return { width: 0, height: 0, lines: [], text: "" } unless width.positive? && height.positive?

      words = rows.select { |row| row[0] == "5" && row[11].to_s.strip != "" && row[10].to_f >= MIN_CONFIDENCE }
      lines = words.group_by { |row| row[2..4] }.values.map do |row|
        left, top = row.map { |w| w[6].to_f }.min, row.map { |w| w[7].to_f }.min
        right = row.map { |w| w[6].to_f + w[8].to_f }.max
        bottom = row.map { |w| w[7].to_f + w[9].to_f }.max
        { text: row.map { |w| w[11].strip }.join(" "), x: pct(left, width), y: pct(top, height),
          w: pct(right - left, width), h: pct(bottom - top, height) }
      end
      { width: width.to_i, height: height.to_i, lines: lines, text: lines.map { |l| l[:text] }.join("\n") }
    end

    def pct(value, total) = (value / total * 100).round(3)
  end
end
