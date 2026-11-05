module Kb
  # Finds a local CLI (tesseract, whisper, ...): $ENV override, Homebrew, ~/.local/bin, then PATH.
  module LocalTool
    module_function

    def path(name, env: nil)
      dirs = [ "/opt/homebrew/bin", File.expand_path("~/.local/bin"), *ENV["PATH"].to_s.split(File::PATH_SEPARATOR) ]
      [ (ENV[env] if env), *dirs.map { |dir| File.join(dir, name) } ].compact.find { |cand| File.file?(cand) && File.executable?(cand) }
    end
  end
end
