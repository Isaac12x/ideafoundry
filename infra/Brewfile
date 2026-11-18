# System dependencies (macOS source of truth). Installed by bin/install and bin/setup via `brew bundle`.
# Linux/Docker equivalents live in the Dockerfile final stage (kept in sync manually). test/brewfile_test.rb fails when the app
# shells out to a tool not declared here.

# Runtime / toolchain
brew "rbenv"            # Ruby version manager (bin/install)
brew "ruby-build"       # rbenv install
brew "node"             # esbuild JS bundles
brew "caddy"            # local HTTPS proxy (bin/install LaunchAgent)
brew "sqlcipher"        # encrypted production SQLite (sqlite3 gem links against it)
brew "vips"             # image_processing / ruby-vips (Active Storage variants)

# KB media toolchain
brew "ffmpeg"           # ffmpeg + ffprobe: video/audio edits, frames, durations, OCR decode
brew "imagemagick"      # magick: image metadata
brew "ghostscript"      # gs: PDF compression
brew "pdftk-java"       # pdftk: PDF page edits
brew "poppler"          # pdfinfo: PDF metadata
brew "pandoc"           # pptx/docx -> HTML document viewer
brew "tesseract"        # Kb::ImageOcr (TESSERACT_BIN)
brew "djvulibre"        # ddjvu: DjVu -> PDF (DDJVU_BIN)
brew "p7zip"            # 7z: archive viewer + project lock (SEVEN_ZIP_BIN)
brew "openai-whisper"   # whisper: local transcripts (WHISPER_BIN)
brew "yt-dlp"           # KB video downloads (YT_DLP_BIN; ~/.local/bin pipx build wins if present)
# Casks skip hand-installed apps (adopting a different version fails `brew bundle` and keeps `check` red).
cask "calibre" unless File.exist?("/Applications/calibre.app") # ebook-convert: non-EPUB ebooks -> EPUB (EBOOK_CONVERT_BIN)
cask "google-chrome" unless File.exist?("/Applications/Google Chrome.app") # headless print for reader PDFs (CHROME_BIN; Chromium/Brave also work)
