require "fileutils"
require "tmpdir"

module Kb
  # Non-EPUB ebooks (.mobi .azw3 .fb2 ...) become a hidden sidecar ".<name>.epub" next to the book via Calibre's
  # ebook-convert; .djvu becomes ".<name>.pdf" via ddjvu. Same claim/lock/err state files as Kb::Transcript.
  # The sidecar is stale once the source is newer. Missing tools are a first-class state, not an exception.
  module BookConversion
    LOCK_TTL = 30.minutes
    TIMEOUT = 20.minutes.to_i
    CALIBRE_APP_BIN = "/Applications/calibre.app/Contents/MacOS/ebook-convert".freeze # the cask does not put it on PATH
    class Error < StandardError; end

    module_function

    def djvu?(abs) = MediaTypes::DJVU_EXTENSIONS.include?(File.extname(abs).downcase)

    def epub?(abs) = MediaTypes::EPUB_EXTENSIONS.include?(File.extname(abs).downcase)

    def format(abs) = djvu?(abs) ? "pdf" : "epub"

    def tool(abs)
      return LocalTool.path("ddjvu", env: "DDJVU_BIN") if djvu?(abs)

      LocalTool.path("ebook-convert", env: "EBOOK_CONVERT_BIN") || (CALIBRE_APP_BIN if File.executable?(CALIBRE_APP_BIN))
    end

    def install_hint(abs)
      if djvu?(abs)
        "ddjvu is not installed. Install DjVuLibre with `brew install djvulibre` (or set DDJVU_BIN) to read DjVu here."
      else
        "Calibre's ebook-convert is not installed. Install it with `brew install --cask calibre` (or set EBOOK_CONVERT_BIN) to read this format here."
      end
    end

    def sidecar_name(name) = ".#{name}.#{format(name)}"

    def sidecar(abs) = File.join(File.dirname(abs), sidecar_name(File.basename(abs)))

    def ready?(abs) = File.size?(sidecar(abs)).present? && File.mtime(sidecar(abs)) >= File.mtime(abs)

    def state_dir = Rails.env.test? ? Rails.root.join("tmp", "kb_books_test_#{Process.pid}") : Rails.root.join("storage", "kb_books")

    def state_file(abs, ext) = state_dir.join("#{Digest::SHA256.hexdigest(abs)}.#{ext}")

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

    # Converts into a temp dir, then moves the result beside the book. Returns the sidecar path.
    def convert!(abs)
      bin = tool(abs) or raise Error, install_hint(abs)

      Dir.mktmpdir("kb-book") do |dir|
        out = File.join(dir, "out.#{format(abs)}")
        cmd = djvu?(abs) ? [ bin, "-format=pdf", abs, out ] : [ bin, abs, out ]
        _stdout, err, status = Subprocess.capture(*cmd, timeout: TIMEOUT)
        raise Error, err.to_s.lines.map(&:strip).reject(&:empty?).last.to_s.truncate(200).presence || "Conversion failed." unless status.success? && File.size?(out)

        target = sidecar(abs)
        FileUtils.cp(out, "#{target}.tmp")
        File.rename("#{target}.tmp", target)
        target
      end
    rescue Subprocess::Timeout => e
      raise Error, "Conversion timed out (#{e.message})."
    ensure
      FileUtils.rm_f(state_file(abs, "lock"))
    end
  end
end
