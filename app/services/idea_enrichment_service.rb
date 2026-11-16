# Enriches an idea by scanning the web for related information.
#
# This service takes an idea and searches the web for:
# - Competitors and similar tools
# - Market landscape and trends
# - Relevant articles and resources
#
# Results are stored in the idea's metadata under the "enrichment" key,
# and competitors/tools found can optionally be added as IdeaEntry records.
#
# Usage:
#   service = IdeaEnrichmentService.new(idea)
#   results = service.enrich
#   service.create_entries_from_results(results)
#
class IdeaEnrichmentService
  ENRICHMENT_SOURCES = %w[competitors market resources].freeze
  SOURCE_LABELS = {
    "competitors" => "Looking for competitors",
    "market" => "Reading market trends",
    "resources" => "Finding tools and resources"
  }.freeze
  STALE_AFTER = 10.minutes

  attr_reader :idea, :user

  def initialize(idea)
    @idea = idea
    @user = idea.user
  end

  # Main entry point. Runs enrichment across all or specified sources.
  # Returns a hash of results keyed by source type.
  def enrich(query: nil, sources: nil)
    search_query = query || build_search_query
    sources ||= ENRICHMENT_SOURCES

    results = {}
    sources.each_with_index do |source, i|
      mark_running(step: "#{SOURCE_LABELS[source] || source} (#{i + 1} of #{sources.size})")
      results[source] = case source
      when "competitors" then search_competitors(search_query)
      when "market"      then search_market(search_query)
      when "resources"   then search_resources(search_query)
      else []
      end
    end

    store_enrichment(results, search_query)
    results
  end

  # Takes enrichment results and creates IdeaEntry records for discovered competitors/tools.
  def create_entries_from_results(results, overwrite: false)
    competitors = results["competitors"] || []
    tools = results["resources"] || []

    if overwrite
      idea.idea_entries.where(kind: [ :competitor, :potential_competitor, :tool ]).destroy_all
    end

    created = []

    competitors.each do |entry|
      next if idea.idea_entries.where(name: entry[:name]).exists?

      kind = entry[:potential] ? :potential_competitor : :competitor
      record = idea.idea_entries.create!(
        name: entry[:name],
        kind: kind,
        url: entry[:url],
        description: entry[:description]
      )
      created << record
    end

    tools.each do |entry|
      next if idea.idea_entries.where(name: entry[:name]).exists?

      record = idea.idea_entries.create!(
        name: entry[:name],
        kind: :tool,
        url: entry[:url],
        description: entry[:description]
      )
      created << record
    end

    created
  end

  # idle | running | done | failed. "running" older than STALE_AFTER counts as failed (worker died).
  def state
    run = idea.metadata&.dig("enrichment_run")
    if run.is_a?(Hash) && run["status"] == "running"
      started = Time.zone.parse(run["started_at"].to_s)
      return started && started > STALE_AFTER.ago ? "running" : "failed"
    end
    return "failed" if error_message.present?
    last_enrichment.present? ? "done" : "idle"
  end

  def error_message
    idea.metadata&.dig("enrichment_error").presence
  end

  def progress_step
    idea.metadata&.dig("enrichment_run", "step")
  end

  # False when no search API key is set: the null adapter can only ever return nothing.
  def search_configured?
    !adapter.is_a?(Adapters::NullAdapter)
  end

  def mark_running(step: "Queued")
    meta = (idea.metadata || {}).except("enrichment_error", "enrichment_failed_at")
    started = meta.dig("enrichment_run", "started_at") || Time.current.iso8601
    meta["enrichment_run"] = { "status" => "running", "started_at" => started, "step" => step }
    idea.update_columns(metadata: meta)
  end

  def mark_failed(message)
    meta = (idea.metadata || {}).except("enrichment_run")
    meta["enrichment_error"] = message
    meta["enrichment_failed_at"] = Time.current.iso8601
    idea.update_columns(metadata: meta)
  end

  def last_enrichment
    idea.metadata&.dig("enrichment")
  end

  def enriched?
    last_enrichment.present? &&
      last_enrichment["enriched_at"].present? &&
      Time.parse(last_enrichment["enriched_at"]) > 24.hours.ago
  end

  private

  # Builds a search query from the idea title and description.
  def build_search_query
    parts = [ idea.title ]
    plain_description = idea.description.to_plain_text.to_s.strip
    if plain_description.present?
      # Take the first ~100 chars of description as context
      parts << plain_description.truncate(100)
    end
    parts.join(" ")
  end

  # Search for competitors in the idea space.
  def search_competitors(query)
    perform_search("#{query} competitors alternatives similar")
  end

  # Search for market trends and landscape.
  def search_market(query)
    perform_search("#{query} market trends landscape opportunity")
  end

  # Search for tools and resources.
  def search_resources(query)
    perform_search("#{query} tools software platform")
  end

  # Performs a web search using the configured search method.
  # Currently uses a pluggable adapter pattern so different search
  # backends can be swapped in.
  def perform_search(query)
    adapter.search(query)
  rescue StandardError => e
    Rails.logger.warn("IdeaEnrichmentService search failed: #{e.message}")
    []
  end

  # Returns the search adapter to use.
  # Defaults to the built-in stub adapter. Configure a real adapter
  # in initializers or via credentials.
  def adapter
    @adapter ||= build_adapter
  end

  def build_adapter
    # Check for API keys in credentials to select the right adapter
    if Rails.application.credentials.dig(:brave, :api_key).present?
      Adapters::BraveSearchAdapter.new
    elsif Rails.application.credentials.dig(:serpapi, :api_key).present?
      Adapters::SerpApiAdapter.new
    else
      # Fallback: no-op adapter that returns empty results.
      # This allows the system to exist without crashing, and can be
      # replaced with a real search provider when one is configured.
      Adapters::NullAdapter.new
    end
  end

  # Stores enrichment results in the idea's metadata.
  def store_enrichment(results, query)
    idea.metadata ||= {}
    idea.metadata = idea.metadata.except("enrichment_run", "enrichment_error", "enrichment_failed_at")
    idea.metadata["enrichment"] = {
      "query" => query,
      "enriched_at" => Time.current.iso8601,
      "results" => serialize_results(results),
      "summary" => build_summary(results)
    }
    idea.save!
  end

  def serialize_results(results)
    results.transform_values do |entries|
      entries.map { |e| e.is_a?(Hash) ? e : { title: e.to_s } }
    end
  end

  def build_summary(results)
    total = results.values.sum { |v| v.is_a?(Array) ? v.size : 0 }
    parts = []
    parts << "#{total} total results"

    if results["competitors"]&.any?
      parts << "#{results["competitors"].size} competitors found"
    end
    if results["market"]&.any?
      parts << "#{results["market"].size} market insights"
    end
    if results["resources"]&.any?
      parts << "#{results["resources"].size} tools/resources found"
    end

    parts.join(", ")
  end
end
