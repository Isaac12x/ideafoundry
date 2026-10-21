require "test_helper"

# Every external tool the app shells out to must be declared in the Brewfile (installed by bin/install
# and bin/setup), so a new tool can't ship without being installed with the app.
class BrewfileTest < ActiveSupport::TestCase
  # tool binary => Brewfile entry that provides it
  PACKAGES = {
    "ffmpeg" => "ffmpeg", "ffprobe" => "ffmpeg", "magick" => "imagemagick", "gs" => "ghostscript",
    "pdftk" => "pdftk-java", "pdfinfo" => "poppler", "pandoc" => "pandoc", "tesseract" => "tesseract",
    "ddjvu" => "djvulibre", "7z" => "p7zip", "whisper" => "openai-whisper", "yt-dlp" => "yt-dlp",
    "ebook-convert" => "calibre", "chrome" => "google-chrome", "caddy" => "caddy", "node" => "node"
  }.freeze
  # Resolved indirectly (constants, name lists, ENV), so the literal scan below can't see them.
  INDIRECT = %w[7z yt-dlp chrome caddy node].freeze
  # OS built-ins / platform-specific, not Homebrew.
  BUILTIN = %w[open osascript which secret-tool git tar].freeze

  CALL = /(?:LocalTool\.path|Open3\.(?:capture[23e]*|popen[23e]*)|Subprocess\.capture|IO\.popen|Process\.spawn|(?<![\w.])(?:system|run!?))\(\s*\[?\s*"([a-z0-9][a-z0-9-]*)"/m

  test "every tool the app shells out to is declared in the Brewfile" do
    declared = Rails.root.join("Brewfile").read.scan(/^\s*(?:brew|cask)\s+"([^"]+)"/).flatten
    used = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map { |f| File.read(f).scan(CALL).flatten }.uniq - BUILTIN

    assert_includes used, "ffmpeg", "scan regex found no tools; it is broken"
    assert_empty used - PACKAGES.keys, "new shell-out tool: add it to the Brewfile and PACKAGES here (Dockerfile is kept in sync manually)"
    assert_empty (used | INDIRECT).map { PACKAGES.fetch(it) } - declared, "Brewfile is missing these packages"
  end
end
