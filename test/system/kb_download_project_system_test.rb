require "application_system_test_case"

# A URL download started while viewing a project must land in that project's Inbox (its top level), not the KB root.
class KbDownloadProjectSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-dl-project-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_downloads.delete_all
    FileUtils.rm_rf(@kb_dir)
  end

  test "download started from the tree while viewing a project lands in its Inbox" do
    visit kb_project_path(src: 0, path: "Ferment")
    assert_selector "turbo-frame#kb-content", text: "Ferment"
    # real right-click on the empty tree area = the root menu
    tree = find(".kb-tree", match: :first)
    page.driver.browser.action.move_to(tree.native, 0, tree.native.size.height / 2 - 6).context_click.perform
    find(".kb-context-menu-item[data-menu-item=download]", visible: true).click
    url = "http://127.0.0.1:#{Capybara.current_session.server.port}/icon.png"
    find("[data-kb-tree-target=promptInput]").send_keys(url, :enter)

    Timeout.timeout(15) { sleep 0.1 until @user.kb_downloads.exists? }
    download = @user.kb_downloads.order(:id).last
    assert_equal "Ferment", download.dir, "download went to the KB root instead of the project"
    KbDownloadJob.perform_now(download.id) # no queue runner under system tests
    assert File.exist?(File.join(@kb_dir, "Ferment", "icon.png")), "file is not in the project"
    refute File.exist?(File.join(@kb_dir, "icon.png")), "file also at the KB root"
  end
end
