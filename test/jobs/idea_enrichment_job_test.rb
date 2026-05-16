require "test_helper"

class IdeaEnrichmentJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.create!(title: "Test Enrichment Idea")
  end

  test "enqueues enrichment job" do
    assert_enqueued_with(job: IdeaEnrichmentJob, args: [@idea.id]) do
      IdeaEnrichmentJob.perform_later(@idea.id)
    end
  end

  test "stores enrichment results in idea metadata" do
    IdeaEnrichmentJob.perform_now(@idea.id)

    @idea.reload
    # With NullAdapter, results will be empty but enrichment metadata should be stored
    assert @idea.metadata["enrichment"].present?
    assert_equal "Test Enrichment Idea", @idea.metadata["enrichment"]["query"]
    assert @idea.metadata["enrichment"]["enriched_at"].present?
  end

  test "handles missing idea gracefully" do
    assert_nothing_raised do
      IdeaEnrichmentJob.perform_now(999999)
    end
  end

  test "creates version when results are found" do
    mock_results = { "competitors" => [{ name: "Test", url: "https://example.com", description: "A test" }] }
    enrich_args = nil
    service = Object.new
    service.define_singleton_method(:enrich) do |query: nil, sources: nil|
      enrich_args = { query: query, sources: sources }
      mock_results
    end

    IdeaEnrichmentService.stub(:new, service) do
      assert_difference -> { @idea.versions.count }, 1 do
        IdeaEnrichmentJob.perform_now(@idea.id)
      end
    end

    assert_equal({ query: nil, sources: nil }, enrich_args)
  end
end
