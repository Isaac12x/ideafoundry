require "test_helper"
require "tmpdir"

class LongOcrPipelineTest < ActiveSupport::TestCase
  def fake_client(markdown: "# Heading\n\nBody text")
    client = Object.new
    client.define_singleton_method(:ocr_pages) { |_images| markdown }
    client
  end

  def fake_supervisor
    supervisor = Object.new
    supervisor.define_singleton_method(:ensure_up!) { true }
    supervisor
  end

  def backend
    LongOcr::Backend.new(env: { "OCR_LONG_BACKEND" => "llamacpp" })
  end

  def run_pipeline(extraction, client: fake_client)
    OcrClient.stub :probe, { "page_count" => 2 } do
      OcrClient.stub :render_page, "PNGBYTES" do
        LongOcr::Pipeline.new(extraction, backend: backend, client: client, supervisor: fake_supervisor).run
      end
    end
  end

  test "KB extraction writes <book>.md beside the source and completes" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "patent.pdf")
      File.write(source, "%PDF-1.4 fake")

      extraction = KnowledgeExtraction.create!(
        source_kind: KnowledgeExtraction::KB_FILE,
        kb_folder_index: 0,
        kb_path: source,
        source_filename: "patent.pdf",
        status: :pending
      )

      run_pipeline(extraction)

      extraction.reload
      assert extraction.complete?
      assert_equal 2, extraction.page_count
      assert_equal 2, extraction.pages_done

      output = File.join(dir, "patent.md")
      assert File.exist?(output), "expected markdown written beside the source"
      assert_includes File.read(output), "Heading"
      assert_equal output, extraction.output_path
      assert File.exist?(source), "original document must be kept"
    end
  end

  test "idea extraction attaches markdown, mirrors ocr_text, and runs enrichment" do
    idea = User.first.ideas.create!(title: "Big book", state: :idea_new)
    idea.attachments.attach(io: StringIO.new("%PDF fake"), filename: "book.pdf", content_type: "application/pdf")
    source = idea.attachments.attachments.last

    extraction = KnowledgeExtraction.create!(
      source_kind: KnowledgeExtraction::IDEA_ATTACHMENT,
      idea_id: idea.id,
      attachment_id: source.id,
      source_filename: "book.pdf",
      status: :pending
    )

    enrich_called = false
    fake_service = Object.new
    fake_service.define_singleton_method(:enrich) { enrich_called = true }

    IdeaEnrichmentService.stub :new, fake_service do
      run_pipeline(extraction)
    end

    extraction.reload
    assert extraction.complete?
    assert enrich_called, "enrichment should run for idea sources"

    source.reload
    assert_equal "complete", source.ocr_status
    assert_includes source.ocr_text, "Heading"

    output = extraction.output_attachment
    assert_not_nil output
    assert_equal "book.extracted.md", output.filename.to_s
    assert_includes output.ocr_text, "Heading"
  end

  test "failure marks extraction failed and surfaces the source error" do
    idea = User.first.ideas.create!(title: "Broken", state: :idea_new)
    idea.attachments.attach(io: StringIO.new("%PDF"), filename: "broken.pdf", content_type: "application/pdf")
    source = idea.attachments.attachments.last

    extraction = KnowledgeExtraction.create!(
      source_kind: KnowledgeExtraction::IDEA_ATTACHMENT,
      idea_id: idea.id,
      attachment_id: source.id,
      source_filename: "broken.pdf",
      status: :pending
    )

    boom = fake_client
    boom.define_singleton_method(:ocr_pages) { |_images| raise "model exploded" }

    assert_raises(RuntimeError) do
      run_pipeline(extraction, client: boom)
    end

    extraction.reload
    assert extraction.failed?
    assert_includes extraction.error, "model exploded"
    assert_equal "failed", source.reload.ocr_status
  end
end
