require "test_helper"

class KnowledgeExtractionJobTest < ActiveJob::TestCase
  test "skips terminal extractions without invoking the pipeline" do
    extraction = KnowledgeExtraction.create!(
      source_kind: KnowledgeExtraction::KB_FILE,
      kb_path: "/tmp/missing.pdf",
      status: :complete
    )

    # No backend / network is touched because the guard returns early.
    assert_nothing_raised { KnowledgeExtractionJob.perform_now(extraction.id) }
    assert extraction.reload.complete?
  end

  test "no-ops when the extraction has been deleted" do
    assert_nothing_raised { KnowledgeExtractionJob.perform_now(-1) }
  end
end
