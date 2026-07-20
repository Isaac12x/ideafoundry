require "test_helper"

class KnowledgeExtractionTest < ActiveJob::TestCase
  def attach_pdf(idea)
    idea.attachments.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "book.pdf", content_type: "application/pdf")
    idea.attachments.attachments.last
  end

  test "enqueue_for_attachment creates row, marks attachment extracting, enqueues job" do
    idea = User.first.ideas.create!(title: "Book idea", state: :idea_new)
    attachment = attach_pdf(idea)

    extraction = nil
    assert_enqueued_with(job: KnowledgeExtractionJob) do
      extraction = KnowledgeExtraction.enqueue_for_attachment(attachment)
    end

    assert extraction.persisted?
    assert extraction.pending?
    assert_equal idea.id, extraction.idea_id
    assert_equal attachment.id, extraction.attachment_id
    assert_equal KnowledgeExtraction::IDEA_ATTACHMENT, extraction.source_kind
    assert_equal "extracting", attachment.reload.ocr_status
  end

  test "enqueue_for_attachment is idempotent while an extraction is active" do
    idea = User.first.ideas.create!(title: "Book idea", state: :idea_new)
    attachment = attach_pdf(idea)

    first = KnowledgeExtraction.enqueue_for_attachment(attachment)
    second = KnowledgeExtraction.enqueue_for_attachment(attachment)

    assert_equal first.id, second.id
    assert_equal 1, KnowledgeExtraction.where(attachment_id: attachment.id).count
  end

  test "progress_percent and active scope" do
    extraction = KnowledgeExtraction.create!(
      source_kind: KnowledgeExtraction::KB_FILE,
      kb_path: "/tmp/x.pdf",
      status: :processing,
      page_count: 4,
      pages_done: 1
    )

    assert_equal 25, extraction.progress_percent
    assert KnowledgeExtraction.active?

    extraction.update!(status: :complete)
    assert_not KnowledgeExtraction.active?
    assert_equal 25, extraction.progress_percent
  end

  test "display_name prefers source filename then kb basename" do
    kb = KnowledgeExtraction.new(source_kind: KnowledgeExtraction::KB_FILE, kb_path: "/books/patent.pdf")
    assert_equal "patent.pdf", kb.display_name
  end
end
