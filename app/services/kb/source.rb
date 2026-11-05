require "fileutils"
require "json"

module Kb
  # Where a downloaded file came from: the link it was fetched from and, for video, the uploader's
  # description. Like the .note.md note, the source of truth is a hidden sidecar next to the file,
  # "<filename>.source.json" ({"url": ..., "description": ...}), so it survives DB loss and rides along
  # on move/rename/delete. Older downloads have no sidecar; the viewer falls back to their kb_downloads row.
  module Source
    SUFFIX = ".source.json".freeze
    MAX_DESCRIPTION = 50_000
    LINK = %r{https?://[^\s<]+}

    module_function

    def sidecar(abs) = "#{abs}#{SUFFIX}"

    def sidecar?(path) = path.to_s.end_with?(SUFFIX)

    def sidecar_for(abs)
      side = sidecar(abs)
      side if !sidecar?(abs) && File.file?(side) && !File.symlink?(side)
    end

    # => { "url" => ..., "description" => ... } (empty when there is no readable sidecar)
    def read(abs)
      side = sidecar_for(abs)
      data = side ? JSON.parse(File.read(side)) : {}
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError, SystemCallError
      {}
    end

    # Only http(s) links are ever shown or followed.
    def safe_url(url)
      url.to_s.strip if url.to_s.strip.match?(%r{\Ahttps?://\S+\z}i)
    end

    def write!(abs, url:, description: nil)
      return unless safe_url(url)

      side = sidecar(abs)
      tmp = "#{side}.tmp"
      raise ArgumentError, "Source path is a symlink." if File.symlink?(side) || File.symlink?(tmp)

      File.write(tmp, JSON.generate({ url: url, description: description.to_s.strip.first(MAX_DESCRIPTION).presence }.compact))
      File.rename(tmp, side)
    end

    # Older downloads have no description: ask yt-dlp for it (no media download, argv only, http(s) only).
    # => :ok | :no_url | :missing_tool | :failed
    def fetch_description!(abs, url)
      url = safe_url(url) or return :no_url
      bin = KbDownloadJob.yt_dlp_bin or return :missing_tool
      out, status = KbDownloadJob.capture([ bin, "--no-playlist", "--skip-download", "--socket-timeout", "10",
                                            "--print", "description", "--", KbDownloadJob.media_url(url) ], timeout: 30)
      text = out.to_s.strip
      return :failed unless status&.success? && text.present? && text != "NA"

      write!(abs, url: url, description: text)
      :ok
    end

    # Callers grab `side = sidecar_for(from)` before moving the file, then call this after.
    def carry!(side, to)
      FileUtils.mv(side, sidecar(to)) if side && !File.exist?(sidecar(to))
    end

    # Escaped text with http(s) links made clickable; never raw HTML from the description.
    def linked_html(text)
      ERB::Util.h(text.to_s).gsub(LINK) do |link|
        url = link.sub(/[.,!?)]+\z/, "")
        %(<a href="#{url}" target="_blank" rel="noopener noreferrer">#{url}</a>#{link.delete_prefix(url)})
      end.html_safe
    end
  end
end
