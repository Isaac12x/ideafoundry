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

  test "creates one history version for a multi-file upload" do
    initial_count = @idea.versions.count
    initial_attachment_count = @idea.attachments.count

    post idea_attachments_url(@idea), params: {
      files: [
        fixture_file_upload("welcome.eml", "message/rfc822"),
        fixture_file_upload("update_with_attachment.eml", "message/rfc822")
      ]
    }

    assert_response :success
    assert_equal initial_count + 1, @idea.versions.count
    assert_equal "Updated media", @idea.latest_version.commit_message
    assert_equal initial_attachment_count + 2, @idea.attachments.count
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
