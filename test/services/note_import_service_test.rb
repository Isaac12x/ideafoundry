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

  test "imports only selected notes when note keys are provided" do
    preview = NoteImportService.new(
      source: "evernote",
      files: [
        MemoryUpload.new("Notebook/Clamp idea.txt", "Adjustable clamp"),
        MemoryUpload.new("Notebook/Shade idea.txt", "Clip-on shade")
      ]
    ).preview

    selected = preview.notes.find { |note| note["title"] == "Shade idea" }

Use teardown methods to clean up the test database.
      NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [],
        selected_note_keys: [selected["note_key"]]
      )
    end

    assert_equal "Shade idea", @user.submissions.recent.first.title
  end

  test "imports selected folders plus explicitly selected notes" do
    preview = NoteImportService.new(
      source: "evernote",
      files: [
        MemoryUpload.new("Inventions/Clamp idea.txt", "Adjustable clamp"),
        MemoryUpload.new("Personal/Shade idea.txt", "Clip-on shade"),
        MemoryUpload.new("Personal/Grocery list.txt", "Milk")
      ]
    ).preview

    inventions = preview.folders.find { |folder| folder.name == "Inventions" }
    shade = preview.notes.find { |note| note["title"] == "Shade idea" }

    assert_difference -> { @user.submissions.count }, 2 do
      result = NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [inventions.key],
        selected_note_keys: [shade["note_key"]]
      )

      assert_equal 2, result.imported_count
      assert_equal 2, result.folder_count
    end

    titles = @user.submissions.recent.limit(2).map(&:title)
    assert_includes titles, "Clamp idea"
    assert_includes titles, "Shade idea"
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

  test "previews Apple Notes from a local sqlite database" do
    path = Rails.root.join("tmp/apple_notes_import_test.sqlite3")
    FileUtils.rm_f(path)

    SQLite3::Database.new(path.to_s) do |db|
      db.execute <<~SQL
        CREATE TABLE ZICCLOUDSYNCINGOBJECT (
          Z_PK INTEGER PRIMARY KEY,
          ZFOLDER INTEGER,
          ZTITLE1 TEXT,
          ZTITLE2 TEXT,
          ZSNIPPET TEXT,
          ZIDENTIFIER TEXT,
          ZMARKEDFORDELETION INTEGER
        )
      SQL
      db.execute "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZTITLE2) VALUES (1, 'Ideas')"
      db.execute "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZFOLDER, ZTITLE1, ZSNIPPET, ZIDENTIFIER, ZMARKEDFORDELETION) VALUES (2, 1, 'Solar shelf', 'Window-mounted collector', 'note-1', 0)"
    end

    preview = AppleNotesImportService.new(database_path: path.to_s).preview

    assert_equal "apple_notes", preview.source
    assert_equal ["Ideas"], preview.folders.map(&:name)
    assert_equal "Solar shelf", preview.notes.first["title"]
    assert_equal "Window-mounted collector", preview.notes.first["body"]
  ensure
    FileUtils.rm_f(path)
  end
end
