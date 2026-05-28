require "test_helper"

class SubmissionImportsControllerTest < ActionDispatch::IntegrationTest
  class MemoryUpload
    attr_reader :original_filename, :content_type

    def initialize(original_filename, content, content_type = "text/plain")
      @original_filename = original_filename
      @content_type = content_type
      @io = StringIO.new(content)
    end

    def read
      @io.read
    end

    def rewind
      @io.rewind
    end
  end

  setup do
    @user = users(:one)
  end

  test "new renders supported note app import options" do
    get new_submission_import_path

    assert_response :success
    assert_select "select[name=?]", "source" do
      assert_select "option[value=?]", "apple_notes"
      assert_select "option[value=?]", "notion"
      assert_select "option[value=?]", "google_keep"
      assert_select "option[value=?]", "evernote"
    end
  end

  test "create imports selected preview folder" do
    preview = NoteImportService.new(
      source: "evernote",
      files: [MemoryUpload.new("Notebook/Clamp idea.txt", "Adjustable clamp")]
    ).preview

    folder = preview.folders.first

    assert_difference "Submission.count", 1 do
      post submission_import_path,
           params: {
             import_payload: preview.encoded_payload,
             folder_keys: [folder.key]
           }
    end

    assert_redirected_to submissions_path(status: "pending", source: "evernote")
    assert_equal "Imported 1 notes from 1 folders into intake.", flash[:notice]
  end
end
