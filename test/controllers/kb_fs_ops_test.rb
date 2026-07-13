require "test_helper"

class KbFsOpsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-fs-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update_kb_folders([@kb_dir])
    @src = 1 # index 0 is the native App KB source
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "creates a markdown file, defaulting the extension" do
    post kb_fs_create_path, params: { src: @src, dir: "", name: "note", kind: "file" }

    assert_redirected_to kb_path(src: @src, file: "note.md")
    assert File.file?(File.join(@kb_dir, "note.md"))
  end

  test "creates a folder that shows in the tree even when empty" do
    post kb_fs_create_path, params: { src: @src, dir: "", name: "research", kind: "folder" }

    assert Dir.exist?(File.join(@kb_dir, "research"))

    get kb_path
    assert_select ".kb-dir-label", text: "research"
  end

  test "rejects names with path separators or leading dots" do
    post kb_fs_create_path, params: { src: @src, dir: "", name: "../evil", kind: "file" }
    assert_equal "Invalid name.", flash[:alert]

    post kb_fs_create_path, params: { src: @src, dir: "", name: ".hidden", kind: "file" }
    assert_equal "Invalid name.", flash[:alert]

    assert_empty Dir.children(@kb_dir)
  end

  test "rejects creating inside a directory outside the source" do
    post kb_fs_create_path, params: { src: @src, dir: "../..", name: "evil", kind: "file" }

    assert_equal "Target folder not found.", flash[:alert]
  end

  test "renames a file keeping its extension, rejects unsupported extensions" do
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_rename_path, params: { src: @src, path: "a.md", name: "b" }
    assert File.file?(File.join(@kb_dir, "b.md"))
    refute File.exist?(File.join(@kb_dir, "a.md"))

    patch kb_fs_rename_path, params: { src: @src, path: "b.md", name: "b.exe" }
    assert_equal "Unsupported file extension.", flash[:alert]
    assert File.file?(File.join(@kb_dir, "b.md"))
  end

  test "moves a file into a subfolder" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_move_path, params: { src: @src, path: "a.md", dest_dir: "sub" }

    assert File.file?(File.join(@kb_dir, "sub", "a.md"))
    refute File.exist?(File.join(@kb_dir, "a.md"))
  end

  test "refuses to move a folder into its own subtree" do
    FileUtils.mkdir_p(File.join(@kb_dir, "a/b"))

    patch kb_fs_move_path, params: { src: @src, path: "a", dest_dir: "a/b" }

    assert_equal "Cannot move a folder into itself.", flash[:alert]
    assert Dir.exist?(File.join(@kb_dir, "a/b"))
  end

  test "deletes folders recursively, refuses paths outside the source" do
    outside = Rails.root.join("tmp", "kb-outside-#{SecureRandom.hex(4)}.md").to_s
    File.write(outside, "keep me")
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.write(File.join(@kb_dir, "sub", "a.md"), "hi")

    delete kb_fs_delete_path, params: { src: @src, path: "../#{File.basename(outside)}" }
    assert_equal "Not found.", flash[:alert]
    assert File.exist?(outside)

    delete kb_fs_delete_path, params: { src: @src, path: "sub" }
    refute Dir.exist?(File.join(@kb_dir, "sub"))
  ensure
    FileUtils.rm_f(outside)
  end

  test "edits and saves markdown content" do
    File.write(File.join(@kb_dir, "a.md"), "before")

    get kb_edit_path(src: @src, file: "a.md")
    assert_response :success
    assert_includes response.body, "kb-editor-textarea"
    assert_includes response.body, "before"

    patch kb_fs_save_path, params: { src: @src, file: "a.md", content: "after" }
    assert_redirected_to kb_file_path(src: @src, file: "a.md")
    assert_equal "after", File.read(File.join(@kb_dir, "a.md"))
  end

  test "rejects operations when the source folder is unavailable" do
    @user.update_kb_folders([Rails.root.join("tmp", "missing-#{SecureRandom.hex(4)}").to_s])

    post kb_fs_create_path, params: { src: @src, dir: "", name: "x", kind: "file" }

    assert_equal "Folder is not available.", flash[:alert]
  end
end
