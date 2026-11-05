require "application_system_test_case"

class KbNamingSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-naming-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "notes"))
    File.write(File.join(@kb_dir, "draft.md"), "# Draft\n")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    # A spinner row keeps kb-tree-sync re-rendering the tree every ~2s.
    @download = @user.kb_downloads.create!(source_index: 0, source_path: @kb_dir, dir: "",
                                           url: "https://example.com/slow", status: "running")
  end

  teardown do
    @download&.destroy
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "renaming a file keeps the input open until the user commits" do
    visit kb_path
    find(".kb-file-row", text: "draft.md").right_click
    find("[data-menu-item=rename]").click

    input = find(".kb-file-row.is-naming .kb-node-name-input")
    input.send_keys([ :command, "a" ], "renam")
    wait_for_tree_rerender
    input = find(".kb-file-row.is-naming .kb-node-name-input")
    assert_equal "renam", input.value
    assert_equal input, page.active_element
    input.send_keys("ed.md", :enter)

    assert_selector ".kb-file-row", text: "renamed.md"
    assert File.exist?(File.join(@kb_dir, "renamed.md"))
  end

  test "a new file drops into naming and stays there" do
    visit kb_path
    find(".kb-dir-header", text: "notes").right_click
    find("[data-menu-item=newFile]").click

    find(".kb-node.is-naming .kb-node-name-input").send_keys([ :command, "a" ], "fre")
    wait_for_tree_rerender
    input = find(".kb-node.is-naming .kb-node-name-input")
    assert_equal "fre", input.value
    assert_equal input, page.active_element
    input.send_keys("sh.md", :enter)

    assert_selector ".kb-file-row", text: "fresh.md"
    assert File.exist?(File.join(@kb_dir, "notes", "fresh.md"))
  end

  private

  # Tag the tree, then wait until a kb-tree-sync re-render swaps it out (tag disappears).
  def wait_for_tree_rerender
    page.execute_script("document.querySelector('.kb-dir-header').dataset.stale = '1'")
    assert_no_selector "[data-stale]", wait: 10
  end
end
