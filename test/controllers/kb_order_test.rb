require "test_helper"

class KbOrderTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-order-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "d"))
    %w[a b c].each { |n| File.write(File.join(@kb_dir, "d", "#{n}.md"), n) }
    @user.update_kb_folders([ @kb_dir ])
    @src = 1
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_entry_preferences.destroy_all
    FileUtils.rm_rf(@kb_dir)
  end

  def pref(dir)
    KbEntryPreference.folder_pref(User.find(@user.id), @kb_dir, dir) # fresh user: no unsaved rows on @user
  end

  def tree_names
    get kb_path
    css_select("#kb-sidebar-tree .kb-dir-children .kb-file-link").map(&:text)
  end

  test "order persists a manual order, switches the folder to manual and survives reload" do
    patch kb_order_path, params: { src: @src, dir: "d", names: %w[c.md a.md b.md] }, as: :turbo_stream

    assert_response :success
    assert_equal %w[a.md b.md c.md], Dir.children(File.join(@kb_dir, "d")).sort # files untouched
    p = pref("d")
    assert_equal "manual_asc", p.sort_mode
    assert_equal %w[c.md a.md b.md], p.order_names
    assert_equal %w[c.md a.md b.md], tree_names
  end

  test "names that do not exist are dropped and unlisted new files sort last" do
    patch kb_order_path, params: { src: @src, dir: "d", names: %w[c.md ghost.md a.md] }, as: :turbo_stream
    File.write(File.join(@kb_dir, "d", "aa.md"), "new")
    Kb::TreeBuilder.bust_cache!(@user)

    assert_equal %w[c.md a.md], pref("d").order_names
    assert_equal %w[c.md a.md aa.md b.md], tree_names
  end

  test "rename, move and delete keep the manual order in step" do
    patch kb_order_path, params: { src: @src, dir: "d", names: %w[c.md a.md b.md] }, as: :turbo_stream

    patch kb_fs_rename_path, params: { src: @src, path: "d/a.md", name: "z.md" }
    assert_equal %w[c.md z.md b.md], pref("d").order_names

    FileUtils.mkdir_p(File.join(@kb_dir, "other"))
    patch kb_fs_move_path, params: { src: @src, path: "d/c.md", dest_dir: "other" }
    assert_equal %w[z.md b.md], pref("d").order_names

    delete kb_fs_delete_path, params: { src: @src, path: "d/b.md" }
    assert_equal %w[z.md], pref("d").order_names
  end

  test "moving between siblings of another folder applies the dropped position" do
    FileUtils.mkdir_p(File.join(@kb_dir, "other"))
    File.write(File.join(@kb_dir, "other", "x.md"), "x")

    patch kb_fs_move_path, params: { src: @src, path: "d/a.md", dest_dir: "other", names: %w[a.md x.md] }

    assert File.file?(File.join(@kb_dir, "other", "a.md"))
    assert_equal %w[a.md x.md], pref("other").order_names
  end

  test "a plain move into a manual folder lands last" do
    patch kb_order_path, params: { src: @src, dir: "d", names: %w[a.md b.md c.md] }, as: :turbo_stream
    File.write(File.join(@kb_dir, "n.md"), "n")

    patch kb_fs_move_path, params: { src: @src, path: "n.md", dest_dir: "d" }

    assert_equal %w[a.md b.md c.md n.md], pref("d").order_names
  end

  test "order refuses folders outside the source" do
    patch kb_order_path, params: { src: @src, dir: "../..", names: %w[a] }, as: :json

    assert_response :unprocessable_content
  end

  test "folder sort override persists, shows in the tree and clears with a blank mode" do
    patch kb_sort_path, params: { src: @src, path: "d", mode: "size_desc" }, as: :turbo_stream
    assert_equal "size_desc", pref("d").sort_mode
    assert_nil @user.reload.settings&.dig("kb", "sort"), "global default untouched"
    assert_select "[data-kb-tree-sort-param='size_desc']"

    patch kb_sort_path, params: { src: @src, path: "d", mode: "" }, as: :turbo_stream
    assert_not pref("d").persisted?, "blank preference rows are removed"

    patch kb_sort_path, params: { src: @src, path: "d", mode: "bogus" }, as: :turbo_stream
    assert_not pref("d").persisted?
  end

  test "root override and the new global modes are accepted" do
    patch kb_sort_path, params: { src: @src, path: "", mode: "manual_asc" }, as: :turbo_stream
    assert_equal "manual_asc", pref("").sort_mode

    %w[added_desc size_asc manual_asc].each do |mode|
      patch kb_sort_path(mode: mode), as: :turbo_stream
      assert_equal mode, @user.reload.settings.dig("kb", "sort")
    end
  end
end
