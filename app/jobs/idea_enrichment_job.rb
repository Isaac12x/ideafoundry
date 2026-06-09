class IdeaEnrichmentJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 30.seconds, attempts: 2

  def perform(idea_id, query: nil, sources: nil)
    idea = Idea.find_by(id: idea_id)
    return unless idea

    service = IdeaEnrichmentService.new(idea)
    results = service.enrich(query: query, sources: sources)

    if results.any?
      idea.create_version("Enriched via web scan — #{results.size} results found")
    end

    results
  rescue StandardError => e
    Rails.logger.error("IdeaEnrichmentJob failed for idea #{idea_id}: #{e.message}")
    idea&.update_columns(
      metadata: idea.metadata&.merge({
        "enrichment_error" => e.message,
        "enrichment_failed_at" => Time.current.iso8601
      })
    )
    raise
  end
end
