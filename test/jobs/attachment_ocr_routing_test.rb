require "test_helper"

# Routing behaviour added for long-document knowledge extraction: PDFs over the
# page threshold are handed to KnowledgeExtractionJob; everything else keeps the
# synchronous Surya path.
class AttachmentOcrRoutingTest < ActiveJob::TestCase
  def attach(idea, filename:, content_type:)
    idea.attachments.attach(io: StringIO.new("data"), filename: filename, content_type: content_type)
    idea.attachments.attachments.last
  end

  test "long PDF is routed to the heavy pipeline instead of Surya" do
    idea = User.first.ideas.create!(title: "Long book", state: :idea_new)
    attachment = attach(idea, filename: "book.pdf", content_type: "application/pdf")

    assert_enqueued_with(job: KnowledgeExtractionJob) do
      OcrClient.stub :probe_attachment, { "needs_long" => true, "page_count" => 240 } do
        AttachmentOcrJob.perform_now(attachment.id)
      end
    end

    assert_equal "extracting", attachment.reload.ocr_status
    assert_equal 1, KnowledgeExtraction.where(attachment_id: attachment.id).count
  end

  test "short PDF stays on the Surya path" do
    idea = User.first.ideas.create!(title: "Short doc", state: :idea_new)
    attachment = attach(idea, filename: "memo.pdf", content_type: "application/pdf")

    OcrClient.stub :probe_attachment, { "needs_long" => false, "page_count" => 2 } do
      OcrClient.stub :extract, { "text" => "hello", "parts" => ["hello"] } do
        AttachmentOcrJob.perform_now(attachment.id)
      end
    end

    assert_equal "complete", attachment.reload.ocr_status
    assert_equal "hello", attachment.ocr_text
    assert_equal 0, KnowledgeExtraction.count
  end

  test "images never probe and never route to the heavy pipeline" do
    idea = User.first.ideas.create!(title: "Image", state: :idea_new)
    attachment = attach(idea, filename: "scan.png", content_type: "image/png")

    # probe_attachment must not be called for non-paged types; stub it to raise.
    OcrClient.stub :probe_attachment, ->(*) { raise "should not probe images" } do
      OcrClient.stub :extract, { "text" => "ocr", "parts" => ["ocr"] } do
        AttachmentOcrJob.perform_now(attachment.id)
      end
    end

    assert_equal "complete", attachment.reload.ocr_status
    assert_equal 0, KnowledgeExtraction.count
  end
end
