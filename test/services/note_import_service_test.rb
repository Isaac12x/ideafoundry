require "test_helper"

class NoteImportServiceTest < ActiveSupport::TestCase
  uses_transaction :test_serializes_simultaneous_retries_of_the_same_preview

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
    assert_equal [ "Archive", "Research" ], preview.folders.map(&:name)
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
        selected_folder_keys: [ inventions.key ]
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

  test "retries of the same preview do not duplicate imported submissions" do
    preview = NoteImportService.new(
      source: "apple_notes",
      files: [
        MemoryUpload.new("Ideas/Solar shelf.md", "Window-mounted collector"),
        MemoryUpload.new("Ideas/Folding shade.md", "Clip-on shade")
      ]
    ).preview
    first_note, second_note = preview.notes

    first_result = NoteImportService.import!(
      user: @user,
      payload: preview.encoded_payload,
      selected_folder_keys: [],
      selected_note_keys: [ first_note["note_key"] ]
    )
    first_submission = @user.submissions.find_by!(source_reference: "#{preview.batch_id}:user-#{@user.id}:0")

    retry_result = NoteImportService.import!(
      user: @user,
      payload: preview.encoded_payload,
      selected_folder_keys: [],
      selected_note_keys: preview.notes.map { |note| note["note_key"] }
    )
    assert_equal 1, retry_result.imported_count

    assert_no_difference -> { @user.submissions.count } do
      replay_result = NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [],
        selected_note_keys: preview.notes.map { |note| note["note_key"] }
      )

      assert_equal 0, replay_result.imported_count
      assert_equal 0, replay_result.folder_count
    end

    assert_equal 1, first_result.imported_count
    assert_equal 1, first_submission.reload.raw_data["events"].size

    other_user = users(:two)
    other_result = NoteImportService.import!(
      user: other_user,
      payload: preview.encoded_payload,
      selected_folder_keys: [],
      selected_note_keys: preview.notes.map { |note| note["note_key"] }
    )

    assert_equal 2, other_result.imported_count
    other_user_references = preview.notes.map do |note|
      "#{preview.batch_id}:user-#{other_user.id}:#{note["import_index"]}"
    end
    assert_equal 2, other_user.submissions.where(source: "apple_notes", source_reference: other_user_references).count
    refute_equal first_submission.source_reference, other_user.submissions.find_by!(source_reference: other_user_references.last).source_reference
  end

  test "recognizes references written by older imports" do
    preview = NoteImportService.new(
      source: "apple_notes",
      files: [ MemoryUpload.new("Ideas/Solar shelf.md", "Window-mounted collector") ]
    ).preview
    note = preview.notes.first

    IntakeSubmissionService.new(
      user: @user,
      title: note["title"],
      body: note["body"],
      source: "apple_notes",
      source_reference: "#{preview.batch_id}:0"
    ).call

    assert_no_difference -> { @user.submissions.count } do
      result = NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [],
        selected_note_keys: [ note["note_key"] ]
      )

      assert_equal 0, result.imported_count
    end
  end

  test "serializes simultaneous retries of the same preview" do
    preview = NoteImportService.new(
      source: "apple_notes",
      files: [ MemoryUpload.new("Ideas/Solar shelf.md", "Window-mounted collector") ]
    ).preview
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    submissions_before = ActiveRecord::Base.uncached { @user.submissions.where(source: "apple_notes").count }

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          result = NoteImportService.import!(
            user: User.find(@user.id),
            payload: preview.encoded_payload,
            selected_folder_keys: [ preview.folders.first.key ]
          )
          outcomes << result.imported_count
        rescue StandardError => error
          outcomes << error
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    imports = 2.times.map { outcomes.pop }
    assert imports.all?(Integer), imports.map(&:inspect).join(", ")
    assert_equal 1, imports.sum
    submissions_after = ActiveRecord::Base.uncached { @user.submissions.where(source: "apple_notes").count }
    assert_equal submissions_before + 1, submissions_after
  ensure
    if preview
      references = preview.notes.map { |note| "#{preview.batch_id}:user-#{@user.id}:#{note["import_index"]}" }
      Submission.where(user: @user, source: "apple_notes", source_reference: references).destroy_all
    end
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

    assert_difference -> { @user.submissions.count }, 1 do
      NoteImportService.import!(
        user: @user,
        payload: preview.encoded_payload,
        selected_folder_keys: [],
        selected_note_keys: [ selected["note_key"] ]
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
        selected_folder_keys: [ inventions.key ],
        selected_note_keys: [ shade["note_key"] ]
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
      labels: [ { name: "Garden" }, { name: "Prototype" } ]
    }.to_json

    preview = NoteImportService.new(
      source: "google_keep",
      files: [ MemoryUpload.new("Takeout/Keep/foldable-shade.json", keep_note, "application/json") ]
    ).preview

    assert_equal [ "Garden", "Prototype" ], preview.folders.map(&:name)
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
    assert_equal [ "Ideas" ], preview.folders.map(&:name)
    assert_equal "Solar shelf", preview.notes.first["title"]
    assert_equal "Window-mounted collector", preview.notes.first["body"]
  ensure
    FileUtils.rm_f(path)
  end
end
