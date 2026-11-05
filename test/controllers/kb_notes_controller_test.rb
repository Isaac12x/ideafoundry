require "test_helper"

class KbNotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-notes-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update_kb_folders([ @kb_dir ])
    @src = 1
    File.binwrite(File.join(@kb_dir, "talk.mp4"), "x")
    File.write(File.join(@kb_dir, "page.md"), "# hi")
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "empty note reads as blank, saving writes the sidecar and renders markdown" do
    get kb_note_path(src: @src, file: "talk.mp4")
    assert_equal "", response.parsed_body["text"]

    patch kb_note_path, params: { src: @src, file: "talk.mp4", text: "**Study** the cold open" }, as: :json
    assert_response :success
    assert_includes response.parsed_body["html"], "<strong>Study</strong>"
    assert_equal "**Study** the cold open\n", File.read(File.join(@kb_dir, "talk.mp4.note.md"))

    patch kb_note_path, params: { src: @src, file: "talk.mp4", text: "" }, as: :json
    refute File.exist?(File.join(@kb_dir, "talk.mp4.note.md"))
  end

  test "refuses markdown targets, notes of notes, missing files and traversal" do
    [ "page.md", "talk.mp4.note.md", "nope.mp4", "../outside.mp4", "/etc/hosts" ].each do |file|
      patch kb_note_path, params: { src: @src, file: file, text: "x" }, as: :json
      assert_response :not_found, file
    end
    assert_equal [ "page.md", "talk.mp4" ], Dir.children(@kb_dir).sort
  end

  test "refuses symlinked media" do
    File.symlink("/etc/hosts", File.join(@kb_dir, "link.mp4"))
    patch kb_note_path, params: { src: @src, file: "link.mp4", text: "x" }, as: :json
    assert_response :not_found
  end

  test "refuses writes while the project is locking" do
    Kb::ProjectLock.stub(:write_block, :busy) do
      patch kb_note_path, params: { src: @src, file: "talk.mp4", text: "x" }, as: :json
    end
    assert_response :conflict
    refute File.exist?(File.join(@kb_dir, "talk.mp4.note.md"))
  end

  test "download form note is passed to the enqueued download" do
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file", name: "https://example.com/a.mp4", note: " study the cold open " }
    assert_equal "study the cold open", @user.kb_downloads.order(:id).last.note
  end
end
