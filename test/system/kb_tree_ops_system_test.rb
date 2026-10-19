require "application_system_test_case"

class KbTreeOpsSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-ops-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "notes"))
    FileUtils.mkdir_p(File.join(@kb_dir, "2024"))
    File.write(File.join(@kb_dir, "draft.md"), "# Draft\n")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "deleting from the context menu confirms, removes the file and updates the tree" do
    visit kb_path
    find(".kb-file-row", text: "draft.md").right_click
    find("[data-menu-item=delete]").click
    find(".app-dialog .btn-danger").click

    assert_no_selector ".kb-file-row", text: "draft.md"
    refute File.exist?(File.join(@kb_dir, "draft.md"))
  end

  test "a new folder shows in the tree right away" do
    visit kb_path
    find(".kb-dir-header", text: "notes").right_click
    find("[data-menu-item=newFolder]").click

    assert_selector ".kb-node.is-naming .kb-node-name-input"
    assert Dir.exist?(File.join(@kb_dir, "notes", "Untitled folder"))
  end

  test "a new project shows in the tree right away" do
    visit kb_path
    find(".kb-dir-header", text: "notes").right_click
    find("[data-menu-item=newProject]").click

    assert_selector ".kb-node.is-naming .kb-node-name-input"
    assert Dir.exist?(File.join(@kb_dir, "notes", "Untitled project"))
  end

  test "deleting a folder removes it from the tree" do
    visit kb_path
    find(".kb-dir-header", text: "notes").right_click
    find("[data-menu-item=delete]").click
    find(".app-dialog .btn-danger").click

    assert_no_selector ".kb-dir-header", text: "notes"
    refute Dir.exist?(File.join(@kb_dir, "notes"))
  end

  test "numeric folder: new project and delete" do
    visit kb_path
    find(".kb-dir-header", text: "2024").right_click
    find("[data-menu-item=newProject]").click
    assert_selector ".kb-node.is-naming .kb-node-name-input"
    assert Dir.exist?(File.join(@kb_dir, "2024", "Untitled project"))
    find("body").send_keys(:escape)
    find(".kb-dir-header", text: "2024").right_click
    find("[data-menu-item=delete]").click
    find(".app-dialog .btn-danger").click
    assert_no_selector ".kb-dir-header", text: "2024"
  end

  test "new project with a file open" do
    visit kb_path
    find(".kb-file-row", text: "draft.md").click
    sleep 1
    find(".kb-dir-header", text: "notes").right_click
    find("[data-menu-item=newProject]").click
    assert_selector ".kb-node.is-naming .kb-node-name-input"
  end

  test "root: new project, name it, then it stays" do
    visit kb_path
    find(".kb-folder-header").right_click
    find("[data-menu-item=newProject]").click
    input = find(".kb-node.is-naming .kb-node-name-input")
    input.send_keys([ :command, "a" ], "Alpha", :enter)
    assert_selector ".kb-node", text: "Alpha"
    assert Dir.exist?(File.join(@kb_dir, "Alpha"))
    sleep 3
    assert_selector ".kb-node", text: "Alpha"
  end

  test "delete works after Turbo navigating away and back (restoration visit)" do
    visit kb_path
    find(".kb-file-row", text: "draft.md").click
    sleep 1
    visit root_path
    page.go_back
    assert_selector ".kb-file-row", text: "draft.md"
    find(".kb-file-row", text: "draft.md").right_click
    find("[data-menu-item=delete]").click
    find(".app-dialog .btn-danger").click
    assert_no_selector ".kb-file-row", text: "draft.md"
  end

  test "delete works after in-app Turbo visits" do
    visit kb_path
    3.times do
      page.execute_script("Turbo.visit('/')")
      sleep 0.7
      page.execute_script("Turbo.visit('#{kb_path}')")
      sleep 0.7
    end
    assert_equal 1, page.evaluate_script("document.querySelectorAll('dialog.app-dialog').length")
    find(".kb-file-row", text: "draft.md").right_click
    find("[data-menu-item=delete]").click
    find(".app-dialog .btn-danger").click
    assert_no_selector ".kb-file-row", text: "draft.md"
  end
end
