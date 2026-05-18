require "test_helper"

class IdeaAttachmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first
    @idea = @user.ideas.create!(title: "Attachment OCR", state: :idea_new)
    @first = attach_file("first.txt", "First attachment")
    @second = attach_file("second.txt", "Second attachment")
  end

  test "reorders idea attachments" do
    patch reorder_idea_attachments_url(@idea), params: {
      attachment_ids: [@second.id, @first.id]
    }

    assert_response :success
    assert_equal [@second.id, @first.id], @idea.ordered_attachments.map(&:id)
    assert_equal 1, @second.reload.position
    assert_equal 2, @first.reload.position
  end

  test "ocr endpoint enqueues extraction for an attachment" do
    assert_enqueued_with(job: AttachmentOcrJob, args: [@first.id]) do
      post ocr_idea_attachment_url(@idea, @first)
    end

    assert_redirected_to edit_idea_url(@idea)
    assert_equal "queued", @first.reload.ocr_status
  end

  private

  def attach_file(filename, body)
    @idea.attachments.attach(
      io: StringIO.new(body),
      filename: filename,
      content_type: "text/plain"
    )
    @idea.attachments.last
  end
end
