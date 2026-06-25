require "test_helper"

# Reproduces the dropzone upload: the browser fetch sends Accept: application/json,
# so render_to_string must still find the HTML partial (idea_attachments/_item.html.erb).
class IdeaAttachmentsJsonFormatTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first
    @idea = @user.ideas.create!(title: "JSON upload", state: :idea_new)
  end

  test "create returns rendered item html when request format is JSON" do
    assert_difference -> { @idea.attachments.count }, 2 do
      post idea_attachments_url(@idea),
        params: { files: [
          fixture_file_upload("welcome.eml", "message/rfc822"),
          fixture_file_upload("update_with_attachment.eml", "message/rfc822")
        ] },
        headers: { "Accept" => "application/json" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_includes body["html"], "current-attachments__item"
  end

  test "update returns rendered item html when request format is JSON" do
    @idea.attachments.attach(io: StringIO.new("hi"), filename: "a.txt", content_type: "text/plain")
    attachment = @idea.attachments_attachments.first

    patch idea_attachment_url(@idea, attachment),
      params: { filename: "renamed.txt" },
      headers: { "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_includes body["html"], "current-attachments__item"
  end
end
