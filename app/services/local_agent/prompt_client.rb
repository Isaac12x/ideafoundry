require "net/http"
require "uri"

module LocalAgent
  class PromptClient
    DEFAULT_BASE_URL = "http://127.0.0.1:8080/v1".freeze
    DEFAULT_MODEL = "gpt-3.5-turbo".freeze
    REQUEST_TIMEOUT = 10.minutes

    class Error < StandardError; end

    def initialize(
      base_url: ENV["LOCAL_INFERENCE_BASE_URL"].presence || ENV["LLAMA_SERVER_BASE_URL"].presence || DEFAULT_BASE_URL,
      model: ENV["LOCAL_INFERENCE_MODEL"].presence || ENV["HERMES_MODEL"].presence || DEFAULT_MODEL
    )
      @base_url = base_url.to_s.delete_suffix("/")
      @model = model.to_s
      validate_local_endpoint!
    end

    def call(instruction:, context:)
      uri = URI("#{base_url}/chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        model: model,
        temperature: 0.2,
        messages: [
          {
            role: "system",
            content: "You are Idea Foundry's local knowledge-base assistant. Work only from the explicitly provided local context. Return a useful, self-contained Markdown result. Do not claim you changed files or performed actions."
          },
          {
            role: "user",
            content: "Request:\n#{instruction}\n\nSelected knowledge-base context:\n#{context}"
          }
        ]
      )

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: REQUEST_TIMEOUT
      ) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Local AI server returned #{response.code}: #{response.body.to_s.truncate(240)}"
      end

      content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s.strip
      raise Error, "Local AI server returned an empty result" if content.blank?

      content
    rescue JSON::ParserError => error
      raise Error, "Local AI server returned invalid JSON: #{error.message}"
    rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => error
      raise Error, "Local AI server is unavailable: #{error.message}"
    end

    private

    attr_reader :base_url, :model

    def validate_local_endpoint!
      uri = URI(base_url)
      allowed_hosts = %w[127.0.0.1 localhost ::1 host.docker.internal]
      raise Error, "AI jobs require a local inference endpoint" unless allowed_hosts.include?(uri.hostname)
    rescue URI::InvalidURIError
      raise Error, "Local AI endpoint is invalid"
    end
  end
end
