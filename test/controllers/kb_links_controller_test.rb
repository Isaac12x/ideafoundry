require "test_helper"

class KbLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-links-test-#{SecureRandom.hex(6)}").to_s
    %w[a b].each { |d| FileUtils.mkdir_p(File.join(@kb_dir, d)) }
    File.write(File.join(@kb_dir, "a", "note.md"), "canonical bytes")
    File.write(File.join(@kb_dir, "b", "other.md"), "other")
    @user.update_kb_folders([ @kb_dir ])
    @src = 1
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_links.destroy_all
    FileUtils.rm_rf(@kb_dir)
  end

  def make_alias
    post kb_aliases_path, params: { src: @src, path: "a/note.md", dest_src: @src, dest_dir: "b" }, as: :turbo_stream
  end

  test "alias shows in the target folder, opens the canonical file and duplicates no bytes" do
    make_alias

    assert_response :success
    link = @user.kb_links.aliases.first
    assert_equal [ "a/note.md", "b/note.md" ], [ link.relative_path, link.peer_relative_path ]
    refute File.exist?(File.join(@kb_dir, "b", "note.md"))
    get kb_path
    assert_select ".kb-alias-row .kb-file-link[href*='a%2Fnote.md'], .kb-alias-row .kb-file-link[href*='a/note.md']", text: "note.md"
    assert_select ".kb-alias-row.is-broken", count: 0
  end

  test "alias refuses folders, name clashes and bad destinations" do
    post kb_aliases_path, params: { src: @src, path: "a", dest_src: @src, dest_dir: "b" }, as: :json
    assert_response :unprocessable_content

    File.write(File.join(@kb_dir, "b", "note.md"), "clash")
    post kb_aliases_path, params: { src: @src, path: "a/note.md", dest_src: @src, dest_dir: "b" }, as: :json
    assert_response :unprocessable_content

    post kb_aliases_path, params: { src: @src, path: "a/note.md", dest_src: @src, dest_dir: "../.." }, as: :json
    assert_response :unprocessable_content
    assert_equal 0, @user.kb_links.count
  end

  test "alias follows canonical rename and move, dangles when canonical is deleted, and can be removed" do
    make_alias

    patch kb_fs_rename_path, params: { src: @src, path: "a/note.md", name: "renamed.md" }
    assert_equal "a/renamed.md", @user.kb_links.aliases.first.relative_path
    assert_equal "b/note.md", @user.kb_links.aliases.first.peer_relative_path

    patch kb_fs_move_path, params: { src: @src, path: "a/renamed.md", dest_dir: "" }
    assert_equal "renamed.md", @user.kb_links.aliases.first.relative_path

    delete kb_fs_delete_path, params: { src: @src, path: "renamed.md" }
    get kb_path
    assert_select ".kb-alias-row.is-broken", count: 1

    delete kb_alias_path(@user.kb_links.aliases.first), as: :turbo_stream
    assert_equal 0, @user.kb_links.count
  end

  test "alias slot moves with its folder and is dropped with it" do
    make_alias

    patch kb_fs_rename_path, params: { src: @src, path: "b", name: "b2" }
    assert_equal "b2/note.md", @user.kb_links.aliases.first.peer_relative_path

    delete kb_fs_delete_path, params: { src: @src, path: "b2" }
    assert_equal 0, @user.kb_links.count
  end

  test "alias of a private project file is flagged private and slot paths never resolve to bytes" do
    File.write(File.join(@kb_dir, "a", Kb::Project::META_FILE), { "name" => "P", "private" => true }.to_yaml)
    make_alias

    get kb_path
    assert_select ".kb-alias-row[data-kb-tree-private-param='true']"
    get kb_file_path(src: @src, file: "b/note.md")
    assert_no_match(/canonical bytes/, response.body, "the alias slot is not a file; only the canonical path serves")
  end

  test "alias can be reordered in a manual folder" do
    make_alias
    patch kb_order_path, params: { src: @src, dir: "b", names: %w[note.md other.md] }, as: :turbo_stream

    assert_equal %w[note.md other.md], KbEntryPreference.folder_pref(User.find(@user.id), @kb_dir, "b").order_names
  end

  test "related links are bidirectional, unique, shown on both file views and removable" do
    post kb_related_links_path, params: { src: @src, path: "a/note.md", peer_src: @src, peer_path: "b/other.md" }, as: :turbo_stream
    assert_response :success
    assert_equal 1, @user.kb_links.related.count

    post kb_related_links_path, params: { src: @src, path: "b/other.md", peer_src: @src, peer_path: "a/note.md" }, as: :json
    assert_response :unprocessable_content
    post kb_related_links_path, params: { src: @src, path: "a/note.md", peer_src: @src, peer_path: "a/note.md" }, as: :json
    assert_response :unprocessable_content

    get kb_file_path(src: @src, file: "a/note.md")
    assert_select ".kb-related__item a", text: "b/other.md"
    get kb_file_path(src: @src, file: "b/other.md")
    assert_select ".kb-related__item a", text: "a/note.md"

    patch kb_fs_rename_path, params: { src: @src, path: "b/other.md", name: "moved.md" }
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select ".kb-related__item a", text: "b/moved.md"

    delete kb_related_link_path(@user.kb_links.related.first), as: :turbo_stream
    assert_equal 0, @user.kb_links.count
  end

  test "deleting a related file drops the link" do
    post kb_related_links_path, params: { src: @src, path: "a/note.md", peer_src: @src, peer_path: "b/other.md" }, as: :turbo_stream
    delete kb_fs_delete_path, params: { src: @src, path: "b/other.md" }

    assert_equal 0, @user.kb_links.count
  end

  test "related is a compact header trigger, chips only when linked, hint in the popover" do
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select ".kb-file-meta .kb-related__trigger"
    assert_select ".kb-related__list", count: 0
    assert_select ".kb-related__hint"

    post kb_related_links_path, params: { src: @src, path: "a/note.md", peer_src: @src, peer_path: "b/other.md" }, as: :turbo_stream
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select ".kb-related__list .kb-related__item", count: 1
  end

  test "References only for a saved page that still sits at its download path" do
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select "a", text: /References/, count: 0

    dl = @user.kb_downloads.create!(url: "https://example.com/p", source_index: @src, source_path: @kb_dir, dir: "a", filename: "note.md", status: "done")
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select "a", text: /References/

    patch kb_fs_rename_path, params: { src: @src, path: "a/note.md", name: "renamed" }
    assert_equal "a/renamed.md", dl.reload.file_rel
    File.write(File.join(@kb_dir, "a", "note.md"), "a stranger")
    get kb_file_path(src: @src, file: "a/note.md")
    assert_select "a", text: /References/, count: 0
  end

  test "alias rows carry canonical info and context-menu params" do
    make_alias
    get kb_path
    assert_select ".kb-alias-row[title='Also in: a/note.md'][data-kb-tree-link-id-param][data-kb-tree-target-rel-param='a/note.md']"
    assert_select "[data-menu-item=aliasReveal]"
  end
end
