require "test_helper"

class NoteImportServiceTest < ActiveSupport::TestCase
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

  test "previews exported notes grouped by folder path" do
    preview = NoteImportService.new(
      source: "notion",
      files: [
        MemoryUpload.new("Research/Solar shelf.md", "# Solar shelf\n\nWindow-mounted collector"),
        MemoryUpload.new("Archive/Old motor.txt", "Archived motor note")
      ]
    ).preview

    assert_equal "notion", preview.source
    assert_equal 2, preview.total_notes
    assert_equal ["Archive", "Research"], preview.folders.map(&:name)
  end

  test "imports only notes from selected folders into intake" do
    preview = NoteImportService.new(
      source: "apple_notes",
      files: [
        MemoryUpload.new("Inventions/Solar shelf.md", "# Solar shelf\n\nWindow-mounted collector"),
        MemoryUpload.new("Personal/Grocery list.txt", "Milk\nBread")
      ]
    ).preview

    inventions = preview.folders.find { |folder| folder.name == "Inventions" }

    assert_difference -> { @user.submissions.count }, 1 do
      result = NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [inventions.key]
      )

      assert_equal 1, result.imported_count
      assert_equal "apple_notes", result.source
    end

    submission = @user.submissions.recent.first
    assert_equal "Solar shelf", submission.title
    assert_equal "apple_notes", submission.source
    assert_includes submission.body, "Window-mounted collector"
    assert_equal "Inventions", submission.raw_data.dig("events", 0, "payload", "import", "folders").first
  end

  test "uses Google Keep labels as selectable folders" do
    keep_note = {
      title: "Foldable shade",
      textContent: "Clip-on shade concept",
      labels: [{ name: "Garden" }, { name: "Prototype" }]
    }.to_json

    preview = NoteImportService.new(
      source: "google_keep",
      files: [MemoryUpload.new("Takeout/Keep/foldable-shade.json", keep_note, "application/json")]
    ).preview

    assert_equal ["Garden", "Prototype"], preview.folders.map(&:name)
  end
end
