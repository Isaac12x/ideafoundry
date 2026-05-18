require "net/http"
require "uri"

class LocalVoiceIdClient
  DEFAULT_URL = "http://voice-id:8000".freeze
  HOST_FALLBACK_URL = "http://localhost:8000".freeze
  TRANSCRIBE_PATH = "/transcribe".freeze
  REQUEST_TIMEOUT = 15

  class Error < StandardError; end

  class << self
    def transcribe(audio:, filename:, content_type:, duration_ms: nil, rms: nil)
      new.transcribe(audio:, filename:, content_type:, duration_ms:, rms:)
    end
  end

  def initialize(base_url: ENV.fetch("VOICE_ID_SERVICE_URL", DEFAULT_URL))
    @base_url = base_url.to_s.delete_suffix("/")
  end

  def transcribe(audio:, filename:, content_type:, duration_ms: nil, rms: nil)
    raise Error, "Voice ID audio is missing" if audio.blank?

    response = with_host_fallback do
      post_audio(audio:, filename:, content_type:, duration_ms:, rms:)
    end
    body = JSON.parse(response.body.presence || "{}")

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, body["error"].presence || body["detail"].presence || "Local Voice ID service returned #{response.code}"
    end

    {
      transcript: body["transcript"].to_s,
      duration_ms: body["duration_ms"].presence || duration_ms,
      rms: body["rms"].presence || rms
    }
  rescue JSON::ParserError
    raise Error, "Local Voice ID service returned an invalid response"
  rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Local Voice ID service is unavailable: #{e.message}"
  end

  private

  attr_reader :base_url

  def with_host_fallback
    yield
  rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout
    raise unless base_url == DEFAULT_URL

    @base_url = ENV.fetch("VOICE_ID_HOST_URL", HOST_FALLBACK_URL).to_s.delete_suffix("/")
    yield
  end

  def post_audio(audio:, filename:, content_type:, duration_ms:, rms:)
    audio.rewind if audio.respond_to?(:rewind)

    uri = URI.join(base_url, TRANSCRIBE_PATH)
    request = Net::HTTP::Post.new(uri)
    request.set_form([
      ["audio", audio, { filename: filename.presence || "voice-id.webm", content_type: content_type.presence || "audio/webm" }],
      ["duration_ms", duration_ms.to_s],
      ["rms", rms.to_s]
    ], "multipart/form-data")

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: REQUEST_TIMEOUT, read_timeout: REQUEST_TIMEOUT) do |http|
      http.request(request)
    end
  end
end
