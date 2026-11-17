require "net/http"

# Proxies dictated audio to the local audio service (the browser cannot reach it: no CORS) and returns the
# auto-formatted text. Auth/lock come from ApplicationController; CSRF stays on (JS sends X-CSRF-Token).
class TranscriptionsController < ApplicationController
  CONTENT_TYPES = %w[audio/wav audio/x-wav audio/mp4 audio/m4a audio/mpeg audio/flac].freeze
  MAX_BYTES = 50.megabytes

  def create
    return render(json: { error: "Unsupported audio type" }, status: :unsupported_media_type) unless CONTENT_TYPES.include?(request.media_type)

    audio = request.raw_post
    return render(json: { error: "No audio" }, status: :unprocessable_content) if audio.blank?
    return render(json: { error: "Audio too large" }, status: :payload_too_large) if audio.bytesize > MAX_BYTES

    response = forward(audio)
    if response.code == "503" # busy: retry once
      sleep 1.5
      response = forward(audio)
    end

    case response.code.to_i
    when 200..299
      data = JSON.parse(response.body)
      render json: { text: (data["enhancedText"].presence || data["text"]).to_s.strip }
    when 503 then render json: { error: "Voice service busy, try again" }, status: :service_unavailable
    when 422 then render json: { error: "Too short — hold for at least a second" }, status: :unprocessable_content
    else render json: { error: "Voice service error" }, status: :bad_gateway
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout
    render json: { error: "Voice service offline" }, status: :service_unavailable
  rescue Net::ReadTimeout, JSON::ParserError
    render json: { error: "Voice service error" }, status: :bad_gateway
  end

  private

  def forward(audio)
    uri = URI("#{ENV.fetch('AUDIO_API_URL', 'http://127.0.0.1:8787')}/transcribe")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 150) do |http|
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = request.media_type
      req["Content-Length"] = audio.bytesize.to_s
      req.body = audio
      http.request(req)
    end
  end
end
