require "json"
require "open3"

module Kb
  class MediaInspector
    def initialize(path, runner: Open3.method(:capture3))
      @path = path
      @runner = runner
    end

    def call
      base = { size: File.size(path), extension: File.extname(path).downcase }

      case MediaTypes.kind_for(path)
      when :video, :audio then base.merge(probe_av)
      when :image then base.merge(probe_image)
      when :pdf then base.merge(probe_pdf)
      else base
      end
    rescue StandardError
      base || {}
    end

    private

    attr_reader :path, :runner

    def probe_av
      out, = run(
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=codec_type,width,height,channels,sample_rate",
        "-of", "json", path
      )
      data = JSON.parse(out)
      video = Array(data["streams"]).find { |stream| stream["codec_type"] == "video" }
      audio = Array(data["streams"]).find { |stream| stream["codec_type"] == "audio" }

      {
        duration: data.dig("format", "duration").to_f.round(3),
        width: video&.fetch("width", nil),
        height: video&.fetch("height", nil),
        channels: audio&.fetch("channels", nil),
        sample_rate: audio&.fetch("sample_rate", nil)&.to_i,
        has_audio: audio.present?
      }
    end

    def probe_image
      out, = run("magick", "identify", "-format", "%w %h", "--", path)
      width, height = out.split.map(&:to_i)
      { width: width, height: height }
    end

    def probe_pdf
      out, = run("pdfinfo", path)
      pages = out[/^Pages:\s+(\d+)/, 1]
      { page_count: pages&.to_i }
    end

    def run(*command)
      stdout, stderr, status = runner.call(*command)
      raise stderr unless status.success?

      [stdout, stderr]
    end
  end
end
