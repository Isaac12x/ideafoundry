require "json"
require "net/http"
require "uri"
require "zlib"

module Adapters
  # Brave Search API adapter.
  # Configure via credentials: rails credentials:edit
  #   brave:
  #     api_key: YOUR_BRAVE_API_KEY
  #
  class BraveSearchAdapter
    def search(query)
      api_key = Rails.application.credentials.dig(:brave, :api_key)
      raise "Brave API key not configured" unless api_key.present?

      uri = URI("https://api.search.brave.com/res/v1/web/search")
      uri.query = URI.encode_www_form({
        q: query,
        count: 10,
        text_decorations: false
      })

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Accept-Encoding"] = "gzip"
      request["X-Subscription-Token"] = api_key

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Brave Search API error: #{response.code} #{response.body}")
        return []
      end

      body = response.body
      body = Zlib.gunzip(body) if response["Content-Encoding"] == "gzip"

      data = JSON.parse(body)
      (data.dig("web", "results") || []).map do |result|
        {
          name: result["title"],
          url: result["url"],
          description: result["description"].to_s.truncate(500),
          potential: result["description"].to_s.downcase.include?("alternative") ||
                     result["description"].to_s.downcase.include?("competitor")
        }
      end
    end
  end
end
