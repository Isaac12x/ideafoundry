require "net/http"
require "json"

class OcrClient
  DEFAULT_URL = "http://ocr:8000/extract".freeze

  class Error < StandardError; end

  def self.extract(attachment)
    new.extract(attachment)
  end

  # Page-count probe used to route between the synchronous Surya path and the
  # heavy on-demand pipeline. Accepts raw bytes so both ActiveStorage blobs and
  # filesystem KB files can be probed.
  def self.probe(bytes:, filename:, content_type:)
    new.probe(bytes: bytes, filename: filename, content_type: content_type)
  end

  def self.probe_attachment(attachment)
    probe(
      bytes: attachment.blob.download,
      filename: attachment.filename.to_s,
      content_type: attachment.blob.content_type
    )
  end

  # Rasterize a single page to PNG bytes (1-indexed) for the heavy pipeline.
  def self.render_page(bytes:, filename:, content_type:, page:, dpi: nil)
    new.render_page(bytes: bytes, filename: filename, content_type: content_type, page: page, dpi: dpi)
  end

  def initialize(
    endpoint: ENV.fetch("OCR_SERVICE_URL", DEFAULT_URL),
    timeout: ENV.fetch("OCR_SERVICE_TIMEOUT", "900").to_i
  )
    @uri = URI(endpoint)
    @timeout = timeout
  end

  def extract(attachment)
    response = post(
      path: @uri.path,
      body: attachment.blob.download,
      content_type: attachment.blob.content_type || "application/octet-stream",
      filename: attachment.filename.to_s,
      read_timeout: @timeout
    )

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OCR service returned #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "OCR service returned invalid JSON: #{e.message}"
  end

  def probe(bytes:, filename:, content_type:)
    response = post(
      path: "/probe",
      body: bytes,
      content_type: content_type || "application/octet-stream",
      filename: filename,
      read_timeout: 30
    )

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OCR probe returned #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "OCR probe returned invalid JSON: #{e.message}"
  end

  def render_page(bytes:, filename:, content_type:, page:, dpi: nil)
    query = "page=#{page.to_i}"
    query += "&dpi=#{dpi.to_i}" if dpi
    response = post(
      path: "/render",
      query: query,
      body: bytes,
      content_type: content_type || "application/octet-stream",
      filename: filename,
      read_timeout: @timeout
    )

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OCR render returned #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    response.body
  end

  private

  def post(path:, body:, content_type:, filename:, read_timeout:, query: nil)
    uri = @uri.dup
    uri.path = path
    uri.query = query
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: read_timeout, open_timeout: 5) do |http|
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = content_type
      request["X-Filename"] = filename
      request.body = body
      http.request(request)
    end
  end
end
