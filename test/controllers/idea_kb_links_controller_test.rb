require "test_helper"

class IdeaKbLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-links-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "Lab", "Tests"))
    File.write(File.join(@kb_dir, "Lab", ".kb-project.yml"), "id: x\ngoal: find out\nstatus: active\nprivate: true\n")
    File.write(File.join(@kb_dir, "Lab", "notes.md"), "hi")
    File.write(File.join(@kb_dir, ".hidden.md"), "no")
    @user.update_kb_folders([ @kb_dir ])
    @src = 1
    @idea = @user.ideas.create!(title: "Linker")
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "search ranks projects first and skips dotfiles" do
    get search_idea_kb_links_path(@idea), params: { q: "l" }
    results = response.parsed_body["results"]
    assert_equal "project", results.first["type"]
    assert_equal "Lab", results.first["name"]
    assert results.none? { |r| r["name"].start_with?(".") }
  end

  test "search finds media by its note text and hides the note sidecar" do
    File.binwrite(File.join(@kb_dir, "talk.mp4"), "x")
    File.write(File.join(@kb_dir, "talk.mp4.note.md"), "pacing reference\n")
    get search_idea_kb_links_path(@idea), params: { q: "pacing" }
    assert_equal [ "talk.mp4" ], response.parsed_body["results"].map { |r| r["name"] }
    get search_idea_kb_links_path(@idea), params: { q: "talk" }
    assert_equal [ "talk.mp4" ], response.parsed_body["results"].map { |r| r["name"] }
  end

  test "create links a project and a file, destroy unlinks" do
    post idea_kb_links_path(@idea), params: { src: @src, path: "Lab" }
    post idea_kb_links_path(@idea), params: { src: @src, path: "Lab/notes.md" }
    assert_equal %w[file project], @idea.kb_links.pluck(:entry_type).sort

    get idea_path(@idea)
    assert_includes response.body, "notes.md"

    assert_difference -> { @idea.kb_links.count }, -1 do
      delete idea_kb_link_path(@idea, @idea.kb_links.first)
    end
  end

  test "create rejects traversal, hidden and missing paths" do
    [ "../etc", ".hidden.md", "nope.md", "" ].each do |path|
      assert_no_difference -> { IdeaKbLink.count } do
        post idea_kb_links_path(@idea), params: { src: @src, path: path }
      end
      assert_response :unprocessable_content
    end
  end

  test "destroy is scoped to the idea" do
    other = @user.ideas.create!(title: "Other")
    link = other.kb_links.create!(source_path: @kb_dir, relative_path: "Lab", entry_type: "project")
    delete idea_kb_link_path(@idea, link)
    assert_response :not_found
    assert IdeaKbLink.exists?(link.id)
  end

  test "kb rename, move and delete keep links in step" do
    link = @idea.kb_links.create!(source_path: @kb_dir, relative_path: "Lab/notes.md", entry_type: "file")
    FileUtils.mkdir_p(File.join(@kb_dir, "Other"))

    patch kb_fs_rename_path, params: { src: @src, path: "Lab", name: "Lab2" }
    assert_equal "Lab2/notes.md", link.reload.relative_path

    patch kb_fs_move_path, params: { src: @src, path: "Lab2/notes.md", dest_dir: "Other" }
    assert_equal "Other/notes.md", link.reload.relative_path

    delete kb_fs_delete_path, params: { src: @src, path: "Other/notes.md" }
    assert_not IdeaKbLink.exists?(link.id)
  end
end
