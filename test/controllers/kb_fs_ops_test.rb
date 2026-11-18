require "test_helper"

class KbFsOpsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-fs-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update_kb_folders([ @kb_dir ])
    @src = 1 # index 0 is the native App KB source
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "creates a markdown file, defaulting the extension" do
    post kb_fs_create_path, params: { src: @src, dir: "", name: "note", kind: "file" }

    assert_redirected_to kb_edit_path(src: @src, file: "note.md")
    assert File.file?(File.join(@kb_dir, "note.md"))
  end

  test "blank-name new file opens in the editor" do
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file" }, as: :turbo_stream

    assert_select "turbo-stream[action=replace][target=kb-content] textarea.kb-editor-textarea"
  end

  test "new file made while viewing a project lands in the project" do
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Proj")
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file", view_rel: "Proj" }, as: :turbo_stream

    assert File.file?(File.join(@kb_dir, "Proj", "Untitled.md"))
    refute File.exist?(File.join(@kb_dir, "Untitled.md"))
  end

  test "project named like an existing file gets a free name" do
    File.write(File.join(@kb_dir, "Plan"), "x")
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "project", name: "Plan" }

    assert File.file?(File.join(@kb_dir, "Plan"))
    assert File.file?(File.join(@kb_dir, "Plan-2", ".kb-project.yml"))
  end

  test "creating a named file over turbo stream opens it in the editor" do
    post kb_fs_create_path, params: { src: @src, dir: "", name: "note", kind: "file" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=kb-content] textarea.kb-editor-textarea"
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

  test "moving an unopened file only refreshes the tree, not the viewer" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.write(File.join(@kb_dir, "a.md"), "hi")
    File.write(File.join(@kb_dir, "open.md"), "open")

    patch kb_fs_move_path, params: { src: @src, path: "a.md", dest_dir: "sub", sel_src: @src, sel_file: "open.md" }, as: :turbo_stream

    assert_select "turbo-stream[action=update][target^=kb-children-]"
    assert_select "turbo-stream[target=kb-content]", false
  end

  test "moving the open file re-points the viewer at its new path" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_move_path, params: { src: @src, path: "a.md", dest_dir: "sub", sel_src: @src, sel_file: "a.md" }, as: :turbo_stream

    assert_select "turbo-stream[target=kb-content]"
    assert_select "turbo-stream[action=kb_url][url*='sub%2Fa.md']"
  end

  test "move patches the cached scan to match a full rescan" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub/deep"))
    FileUtils.mkdir_p(File.join(@kb_dir, "dest"))
    File.write(File.join(@kb_dir, "sub/deep/x.md"), "x")
    File.binwrite(File.join(@kb_dir, "sub/clip.mp4"), "x")
    File.write(File.join(@kb_dir, "sub/clip.vtt"), "WEBVTT\n")
    File.write(File.join(@kb_dir, "dest/keep.md"), "k")
    key = ->(gen) { [ "kb/tree/fs-v6", @user.id, File.expand_path(@kb_dir), gen ] }
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      Kb::TreeBuilder.build(@user) # warm
      FileUtils.mv(File.join(@kb_dir, "sub"), File.join(@kb_dir, "dest/sub"))
      Kb::TreeBuilder.patch!(@user, @kb_dir, "sub", "dest/sub")
      patched = cache.read(key.(Kb::TreeBuilder.cache_generation(@user.id)))
      Kb::TreeBuilder.bust_cache!(@user)
      Kb::TreeBuilder.build(@user)
      full = cache.read(key.(Kb::TreeBuilder.cache_generation(@user.id)))
      strip = ->(list) { list.map { |e| e.slice(:rel, :cc, :size) } }
      assert_equal strip.(full[:files]), strip.(patched[:files])
      assert_equal full[:dirs].map { |d| d[:rel] }, patched[:dirs].map { |d| d[:rel] }
    end
  end

  test "move and create stream only the changed folders" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    FileUtils.mkdir_p(File.join(@kb_dir, "other"))
    File.write(File.join(@kb_dir, "sub/a.md"), "hi")
    File.write(File.join(@kb_dir, "other/b.md"), "hi")

    patch kb_fs_move_path, params: { src: @src, path: "sub/a.md", dest_dir: "other" }, as: :turbo_stream
    assert_select "turbo-stream[action=update][target^=kb-children-]", 2
    assert_select "turbo-stream[target=kb-sidebar-tree]", false

    post kb_fs_create_path, params: { src: @src, dir: "other", name: "n", kind: "file" }, as: :turbo_stream
    assert_select "turbo-stream[action=update][target^=kb-children-]", 1
    assert_select "turbo-stream[target=kb-content] textarea.kb-editor-textarea"
  end

  test "tree lists files that have notes" do
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    Kb::Note.write!(File.join(@kb_dir, "clip.mp4"), "Why I kept this")

    get kb_path(src: @src)

    assert_select ".kb-notes-index a .kb-notes-index__text", text: "Why I kept this"
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

  test "deletes a file via the tree's turbo-stream form post" do
    File.write(File.join(@kb_dir, "a.md"), "hi")

    post kb_fs_delete_path, params: { _method: "delete", src: @src, path: "a.md", sel_src: @src, sel_file: "a.md" },
                            as: :turbo_stream

    assert_response :success
    refute File.exist?(File.join(@kb_dir, "a.md"))
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

  test "new folder with picked files moves them into the placeholder folder" do
    File.write(File.join(@kb_dir, "a.md"), "a")
    File.write(File.join(@kb_dir, "b.md"), "b")

    post kb_fs_create_path, params: { src: @src, dir: "", kind: "folder", move: [ "a.md", "b.md", "../x" ] }, as: :turbo_stream

    assert_response :success
    assert File.file?(File.join(@kb_dir, "Untitled folder", "a.md"))
    assert File.file?(File.join(@kb_dir, "Untitled folder", "b.md"))
    assert_not File.exist?(File.join(@kb_dir, "a.md"))
  end

  test "creating without a name makes a placeholder and flags it for inline naming" do
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file" }, as: :turbo_stream

    assert_response :success
    assert File.file?(File.join(@kb_dir, "Untitled.md"))
    assert_select "input.kb-node-name-input[data-kb-autofocus][value=?]", "Untitled.md"

    post kb_fs_create_path, params: { src: @src, dir: "", kind: "folder" }, as: :turbo_stream

    assert Dir.exist?(File.join(@kb_dir, "Untitled folder"))
  end

  test "unnamed creates never collide" do
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file" }, as: :turbo_stream
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file" }, as: :turbo_stream

    assert File.file?(File.join(@kb_dir, "Untitled.md"))
    assert File.file?(File.join(@kb_dir, "Untitled-2.md"))
  end

  test "renaming as JSON returns the new path instead of a tree" do
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_rename_path, params: { src: @src, path: "a.md", name: "notes" }, as: :json

    assert_response :success
    assert_equal({ "rel" => "notes.md", "name" => "notes.md" }, response.parsed_body)
    assert File.file?(File.join(@kb_dir, "notes.md"))
  end

  test "a JSON rename failure reports the reason without a flash" do
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_rename_path, params: { src: @src, path: "a.md", name: "a.exe" }, as: :json

    assert_response :unprocessable_content
    assert_equal "Unsupported file extension.", response.parsed_body["error"]
    assert_nil flash[:alert]
  end

  test "favouriting as JSON answers silently" do
    File.write(File.join(@kb_dir, "a.md"), "hi")

    patch kb_fs_preference_path,
          params: { src: @src, path: "a.md", entry_type: "file", favorite: "1" },
          as: :json

    assert_response :no_content
    assert_empty response.body
    assert_nil flash[:notice]
    assert @user.kb_entry_preferences.find_by!(relative_path: "a.md").favorite?
  end

  test "create then name leaves exactly one file under the typed name" do
    post kb_fs_create_path, params: { src: @src, dir: "", kind: "file" }, as: :turbo_stream
    patch kb_fs_rename_path,
          params: { src: @src, path: "Untitled.md", name: "Positioning" },
          as: :json

    assert_response :success
    assert_equal [ "Positioning.md" ], Dir.children(@kb_dir)
  end

  test "rejects operations when the source folder is unavailable" do
    @user.update_kb_folders([ Rails.root.join("tmp", "missing-#{SecureRandom.hex(4)}").to_s ])

    post kb_fs_create_path, params: { src: @src, dir: "", name: "x", kind: "file" }

    assert_equal "Folder is not available.", flash[:alert]
  end

  test "inline JSON rename busts the tree cache so the next tree render shows the new name" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Dir.mkdir(File.join(@kb_dir, "Untitled project"))
    get kb_tree_path, as: :turbo_stream
    assert_includes response.body, "Untitled project"

    patch kb_fs_rename_path, params: { src: @src, path: "Untitled project", name: "Alpha" }, as: :json
    assert_response :success

    get kb_tree_path, as: :turbo_stream
    assert_includes response.body, "Alpha"
    refute_includes response.body, "Untitled project"
  ensure
    Rails.cache = original_cache
  end

  test "non-turbo create still busts the tree cache" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    get kb_tree_path, as: :turbo_stream
    post kb_fs_create_path, params: { src: @src, dir: "", name: "fresh", kind: "folder" }
    assert_response :redirect

    get kb_tree_path, as: :turbo_stream
    assert_includes response.body, "fresh"
  ensure
    Rails.cache = original_cache
  end

  test "bust_cache! increments the generation, seeding it when missing" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    assert_equal 0, Kb::TreeBuilder.cache_generation(@user.id)
    Kb::TreeBuilder.bust_cache!(@user)
    assert_equal 1, Kb::TreeBuilder.cache_generation(@user.id)
    Kb::TreeBuilder.bust_cache!(@user)
    assert_equal 2, Kb::TreeBuilder.cache_generation(@user.id)
  ensure
    Rails.cache = original_cache
  end

  test "a failed delete (permissions) reports an alert instead of a bare 500" do
    FileUtils.mkdir_p(File.join(@kb_dir, "locked"))
    File.write(File.join(@kb_dir, "locked", "a.md"), "hi")
    File.chmod(0o555, File.join(@kb_dir, "locked"))
    skip "root can delete anything" if Process.uid.zero?

    delete kb_fs_delete_path, params: { src: @src, path: "locked/a.md" }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "Couldn&#39;t complete that"
  ensure
    File.chmod(0o755, File.join(@kb_dir, "locked"))
  end

  test "download-source sidecar follows its file on rename, move and delete" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    Kb::Source.write!(File.join(@kb_dir, "clip.mp4"), url: "https://example.com/v", description: "d")

    patch kb_fs_rename_path, params: { src: @src, path: "clip.mp4", name: "talk" }
    assert_equal "https://example.com/v", Kb::Source.read(File.join(@kb_dir, "talk.mp4"))["url"]
    refute File.exist?(File.join(@kb_dir, "clip.mp4.source.json"))

    patch kb_fs_move_path, params: { src: @src, path: "talk.mp4", dest_dir: "sub" }
    assert File.file?(File.join(@kb_dir, "sub", "talk.mp4.source.json"))

    delete kb_fs_delete_path, params: { src: @src, path: "sub/talk.mp4" }
    assert_empty Dir.children(File.join(@kb_dir, "sub"))
  end

  test "captions sidecar follows its media on rename, move and delete" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    File.write(File.join(@kb_dir, "clip.vtt"), "WEBVTT\n")

    patch kb_fs_rename_path, params: { src: @src, path: "clip.mp4", name: "talk" }
    assert File.file?(File.join(@kb_dir, "talk.mp4"))
    assert File.file?(File.join(@kb_dir, "talk.vtt"))
    refute File.exist?(File.join(@kb_dir, "clip.vtt"))

    patch kb_fs_move_path, params: { src: @src, path: "talk.mp4", dest_dir: "sub" }
    assert File.file?(File.join(@kb_dir, "sub", "talk.vtt"))
    refute File.exist?(File.join(@kb_dir, "talk.vtt"))

    delete kb_fs_delete_path, params: { src: @src, path: "sub/talk.mp4" }
    assert_empty Dir.children(File.join(@kb_dir, "sub"))
  end

  test "note sidecar follows its file on rename, move and delete" do
    FileUtils.mkdir_p(File.join(@kb_dir, "sub"))
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    File.write(File.join(@kb_dir, "clip.mp4.note.md"), "why\n")

    patch kb_fs_rename_path, params: { src: @src, path: "clip.mp4", name: "talk" }
    assert File.file?(File.join(@kb_dir, "talk.mp4.note.md"))
    refute File.exist?(File.join(@kb_dir, "clip.mp4.note.md"))

    patch kb_fs_move_path, params: { src: @src, path: "talk.mp4", dest_dir: "sub" }
    assert File.file?(File.join(@kb_dir, "sub", "talk.mp4.note.md"))
    refute File.exist?(File.join(@kb_dir, "talk.mp4.note.md"))

    delete kb_fs_delete_path, params: { src: @src, path: "sub/talk.mp4" }
    assert_empty Dir.children(File.join(@kb_dir, "sub"))
  end

  test "screenshot frames folder follows its video on rename and move, never clobbering" do
    FileUtils.mkdir_p([ File.join(@kb_dir, "sub"), File.join(@kb_dir, "clip") ])
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    File.binwrite(File.join(@kb_dir, "clip", "clip \u2014 00m01.5s.png"), "p")
    File.binwrite(File.join(@kb_dir, "clip", "clip \u2014 00m02s.png"), "p")

    patch kb_fs_rename_path, params: { src: @src, path: "clip.mp4", name: "talk" }
    refute Dir.exist?(File.join(@kb_dir, "clip"))
    assert_equal [ "talk \u2014 00m01.5s.png", "talk \u2014 00m02s.png" ], Dir.children(File.join(@kb_dir, "talk")).sort
    assert_equal [ [ "talk \u2014 00m01.5s.png", 1.5 ], [ "talk \u2014 00m02s.png", 2.0 ] ], Kb::VideoShots.list(File.join(@kb_dir, "talk.mp4"))

    patch kb_fs_move_path, params: { src: @src, path: "talk.mp4", dest_dir: "sub" }
    assert File.file?(File.join(@kb_dir, "sub", "talk", "talk \u2014 00m01.5s.png"))
    refute Dir.exist?(File.join(@kb_dir, "talk"))

    # an existing destination folder is merged into: renamed, numbered on collision, nothing overwritten
    FileUtils.mkdir_p(File.join(@kb_dir, "sub", "keep"))
    File.binwrite(File.join(@kb_dir, "sub", "keep", "mine.txt"), "m")
    File.binwrite(File.join(@kb_dir, "sub", "keep", "keep \u2014 00m01.5s.png"), "old")
    File.binwrite(File.join(@kb_dir, "sub", "talk", "extra.png"), "p")
    patch kb_fs_rename_path, params: { src: @src, path: "sub/talk.mp4", name: "keep" }
    keep = File.join(@kb_dir, "sub", "keep")
    assert_equal [ "extra.png", "keep \u2014 00m01.5s 2.png", "keep \u2014 00m01.5s.png", "keep \u2014 00m02s.png", "mine.txt" ], Dir.children(keep).sort
    assert_equal "old", File.read(File.join(keep, "keep \u2014 00m01.5s.png"))
    refute Dir.exist?(File.join(@kb_dir, "sub", "talk"))
  end

  test "deleting a video keeps its screenshots folder (hard delete, user images)" do
    FileUtils.mkdir_p(File.join(@kb_dir, "clip"))
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")
    File.binwrite(File.join(@kb_dir, "clip", "clip \u2014 00m01s.png"), "p")
    delete kb_fs_delete_path, params: { src: @src, path: "clip.mp4" }
    refute File.exist?(File.join(@kb_dir, "clip.mp4"))
    assert File.file?(File.join(@kb_dir, "clip", "clip \u2014 00m01s.png"))
  end
end
