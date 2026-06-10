require "test_helper"

class IdeaEnrichmentServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.create!(title: "AI-Powered Recipe Generator", description: "An app that generates recipes using AI")
  end

  test "builds search query from idea title and description" do
    service = IdeaEnrichmentService.new(@idea)
    query = service.send(:build_search_query)
    assert_includes query, "AI-Powered Recipe Generator"
  end

  test "stores enrichment results in idea metadata" do
    service = IdeaEnrichmentService.new(@idea)
    mock_results = {
      "competitors" => [{ name: "TestComp", url: "https://test.com", description: "A competitor" }],
      "market" => [],
      "resources" => []
    }

    service.stub(:perform_search, mock_results.values.flatten) do
      results = service.enrich
      assert_equal 3, results.keys.length
    end

    @idea.reload
    assert @idea.metadata["enrichment"].present?
    assert_includes @idea.metadata["enrichment"]["query"], "AI-Powered Recipe Generator"
  end

  test "enriched? returns false when never enriched" do
    service = IdeaEnrichmentService.new(@idea)
    refute service.enriched?
  end

  test "enriched? returns true when recently enriched" do
    @idea.update!(metadata: { "enrichment" => { "enriched_at" => 1.hour.ago.iso8601 } })
    service = IdeaEnrichmentService.new(@idea)
    assert service.enriched?
  end

  test "create_entries_from_results creates competitor entries" do
    results = {
      "competitors" => [
        { name: "TestComp", url: "https://test.com", description: "A competitor", potential: false },
        { name: "MaybeComp", url: "https://maybe.com", description: "Possibly a competitor", potential: true }
      ]
    }

    service = IdeaEnrichmentService.new(@idea)
    created = service.create_entries_from_results(results)

    assert_equal 2, created.length
    assert_equal 2, @idea.idea_entries.count

    competitor = @idea.idea_entries.find_by(name: "TestComp")
    assert_equal "competitor", competitor.kind

    potential = @idea.idea_entries.find_by(name: "MaybeComp")
    assert_equal "potential_competitor", potential.kind
  end

  test "create_entries_from_results skips duplicates" do
    @idea.idea_entries.create!(name: "ExistingComp", kind: :competitor)
    results = {
      "competitors" => [
        { name: "ExistingComp", url: "https://test.com", description: "Already exists" }
      ]
    }

    service = IdeaEnrichmentService.new(@idea)
    created = service.create_entries_from_results(results)

    assert_empty created
    assert_equal 1, @idea.idea_entries.where(name: "ExistingComp").count
  end

  test "null adapter returns empty results" do
    adapter = Adapters::NullAdapter.new
    results = adapter.search("test query")
    assert_equal [], results
  end
end
