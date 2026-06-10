require "net/http"
require "json"

class OcrClient
  DEFAULT_URL = "http://ocr:8000/extract".freeze

  class Error < StandardError; end

  def self.extract(attachment)
    new.extract(attachment)
  end

  def initialize(
    endpoint: ENV.fetch("OCR_SERVICE_URL", DEFAULT_URL),
    timeout: ENV.fetch("OCR_SERVICE_TIMEOUT", "900").to_i
  )
    @uri = URI(endpoint)
    @timeout = timeout
  end

  def extract(attachment)
    response = Net::HTTP.start(@uri.host, @uri.port, read_timeout: @timeout, open_timeout: 5) do |http|
      request = Net::HTTP::Post.new(@uri)
      request["Content-Type"] = attachment.blob.content_type || "application/octet-stream"
      request["X-Filename"] = attachment.filename.to_s
      request.body = attachment.blob.download
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OCR service returned #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "OCR service returned invalid JSON: #{e.message}"
  end
end
