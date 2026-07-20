require "test_helper"

class KbEnhancementsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-enhancements-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "research"))
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [@kb_dir], "hide_native" => true }
    ))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "external file upload copies bytes into the dropped folder and streams the tree" do
    upload = Rack::Test::UploadedFile.new(
      StringIO.new("raw research bytes"),
      "application/octet-stream",
      original_filename: "source.bin"
    )

    post kb_fs_upload_path,
         params: { src: 0, dir: "research", files: [upload] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "raw research bytes", File.binread(File.join(@kb_dir, "research", "source.bin"))
    assert_select "turbo-stream[action=replace][target=kb-sidebar-tree]"
    assert_select ".kb-file-link", text: "source.bin"
  end

  test "upload keeps both files when a name already exists" do
    File.write(File.join(@kb_dir, "research", "notes.txt"), "first")
    upload = Rack::Test::UploadedFile.new(StringIO.new("second"), "text/plain", original_filename: "notes.txt")

    post kb_fs_upload_path, params: { src: 0, dir: "research", files: [upload] }

    assert_equal "first", File.read(File.join(@kb_dir, "research", "notes.txt"))
    assert_equal "second", File.read(File.join(@kb_dir, "research", "notes-2.txt"))
  end

  test "generic dropped files remain visible and get a download view" do
    File.binwrite(File.join(@kb_dir, "research", "archive.xyz"), "opaque")

    get kb_path(src: 0, file: "research/archive.xyz")

    assert_response :success
    assert_select ".kb-file-link", text: "archive.xyz"
    assert_select ".kb-generic-file a[data-turbo=false]", text: /Download archive\.xyz/
  end

  test "folder emoji and file favourite update in place" do
    File.write(File.join(@kb_dir, "research", "note.md"), "# Note")

    patch kb_fs_preference_path,
          params: { src: 0, path: "research", entry_type: "folder", icon_kind: "emoji", emoji: "🔬" },
          as: :turbo_stream
    assert_response :success
    assert_select ".kb-entry-icon", text: "🔬"

    patch kb_fs_preference_path,
          params: { src: 0, path: "research/note.md", entry_type: "file", favorite: "1" },
          as: :turbo_stream
    assert_response :success
    preference = @user.kb_entry_preferences.find_by!(relative_path: "research/note.md", entry_type: "file")
    assert preference.favorite?
    assert_select ".kb-favorite-button.is-favorite[data-kb-tree-rel-param=?]", "research/note.md"
  end

  test "uploaded folder icon is stored locally with Active Storage" do
    icon = Rack::Test::UploadedFile.new(
      StringIO.new("\x89PNG\r\n\x1a\n"),
      "image/png",
      original_filename: "lab.png"
    )

    patch kb_fs_preference_path,
          params: { src: 0, path: "research", entry_type: "folder", icon_kind: "image", icon_image: icon },
          as: :turbo_stream

    assert_response :success
    preference = @user.kb_entry_preferences.find_by!(relative_path: "research", entry_type: "folder")
    assert_equal "image", preference.icon_kind
    assert preference.icon_image.attached?
    assert_select ".kb-entry-icon img"
  end

  test "rename carries folder preferences and favourites to the new path" do
    File.write(File.join(@kb_dir, "research", "note.md"), "# Note")
    @user.kb_entry_preferences.create!(
      source_path: @kb_dir,
      relative_path: "research/note.md",
      entry_type: "file",
      favorite: true
    )

    patch kb_fs_rename_path, params: { src: 0, path: "research", name: "sources" }

    preference = @user.kb_entry_preferences.find_by!(entry_type: "file")
    assert_equal "sources/note.md", preference.relative_path
    assert preference.favorite?
  end

  test "tree endpoint returns an in-place Turbo replacement" do
    File.write(File.join(@kb_dir, "research", "note.md"), "# Note")

    get kb_tree_path, params: { sel_src: 0, sel_file: "research/note.md" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=kb-sidebar-tree]"
    assert_select ".kb-file-row.is-active"
  end

  test "Finder action rejects paths outside configured sources" do
    post kb_fs_open_path, params: { src: 0, path: "../../etc" }, as: :json

    assert_response :not_found
  end

  test "display settings store a global knowledge-base folder emoji" do
    patch settings_display_path, params: {
      display_settings: {
        quote: "",
        contrast: "100",
        kb_default_icon_kind: "emoji",
        kb_default_folder_emoji: "🧭"
      }
    }

    assert_redirected_to settings_display_path
    preference = KbEntryPreference.default_folder_for(@user.reload)
    assert preference.persisted?
    assert_equal "emoji", preference.icon_kind
    assert_equal "🧭", preference.emoji

    get settings_display_path
    assert_select "form.display-settings-form[enctype='multipart/form-data']"
    assert_select ".kb-default-icon-settings__glyph", text: "🧭"
  end
end
