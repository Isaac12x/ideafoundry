require "json"
require "net/http"
require "uri"

module Adapters
  # SerpAPI adapter for Google search results.
  # Configure via credentials: rails credentials:edit
  #   serpapi:
  #     api_key: YOUR_SERPAPI_KEY
  #
  class SerpApiAdapter
    def search(query)
      api_key = Rails.application.credentials.dig(:serpapi, :api_key)
      raise "SerpAPI key not configured" unless api_key.present?

      uri = URI("https://serpapi.com/search")
      uri.query = URI.encode_www_form({
        q: query,
        api_key: api_key,
        engine: "google",
        num: 10,
        hl: "en"
      })

      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("SerpAPI error: #{response.code} #{response.body}")
        return []
      end

      data = JSON.parse(response.body)
      (data["organic_results"] || []).map do |result|
        {
          name: result["title"],
          url: result["link"],
          description: result["snippet"].to_s.truncate(500),
          potential: result["snippet"].to_s.downcase.include?("alternative") ||
                     result["snippet"].to_s.downcase.include?("competitor")
        }
      end
    end
  end
end
