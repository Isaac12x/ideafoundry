module Adapters
  # Null adapter. Returns empty results when no search API is configured.
  class NullAdapter
    def search(query)
      Rails.logger.info("IdeaEnrichmentService: No search adapter configured. Query was: #{query}")
      []
    end
  end
end
