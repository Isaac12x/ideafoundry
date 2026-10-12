require "tmpdir"

module Kb
  # Prints a reader-mode HTML document to PDF with headless Chrome.
  module ReaderPdf
    TIMEOUT = 90
    CANDIDATES = [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
    ].freeze

    module_function

    # true when dest was written; false when no browser is available or it failed.
    def write(html, dest)
      bin = browser
      return false unless bin

      Dir.mktmpdir("kb-reader") do |tmp|
        page = File.join(tmp, "page.html")
        File.write(page, html)
        log = File.join(tmp, "chrome.log")
        # Own profile dir so a running Chrome session is never touched.
        pid = Process.spawn(bin, "--headless=new", "--disable-gpu", "--no-first-run",
                            "--user-data-dir=#{tmp}/profile", "--no-pdf-header-footer",
                            "--virtual-time-budget=15000", "--print-to-pdf=#{dest}",
                            "file://#{page}", out: File::NULL, err: log)
        # macOS Chrome often lingers after printing (updater); stop once it logs the write.
        deadline = Time.now + TIMEOUT
        until Process.wait(pid, Process::WNOHANG) || Time.now > deadline
          break if File.binread(log).include?("written to file")
          sleep 0.5
        end
        stop(pid)
      end
      File.size?(dest).to_i.positive?
    end

    def stop(pid)
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def browser
      [ ENV["CHROME_BIN"], *CANDIDATES ].compact.find { |path| File.executable?(path) } ||
        %w[google-chrome chromium chromium-browser].find { |cmd| system("which", cmd, out: File::NULL, err: File::NULL) }
    end
  end
end
