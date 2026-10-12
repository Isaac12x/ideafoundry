require "application_system_test_case"

class KbProjectSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-project-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "create a project, add a test, log two runs and compare them" do
    visit kb_path
    find(".kb-folder-header", match: :first).right_click
    find("[data-menu-item=newProject]").click

    find(".kb-node.is-naming .kb-node-name-input").send_keys([:command, "a"], "Cold chain", :enter)
    assert_selector ".kb-project-link", text: "Cold chain"
    assert Kb::Project.at(@kb_dir, "Cold chain")

    find(".kb-project-link", text: "Cold chain").click
    assert_selector ".kbp-title", text: "Cold chain"

    find(".kbp-edit--inline summary").click
    find("input[name=name]").set("Fridge")
    click_button "Add test"
    assert_selector ".kbp-test-name", text: "Fridge"

    [["2026-10-06", "4.0"], ["2026-10-20", "4.5"]].each do |date, value|
      find(".kbp-log summary").click
      within ".kbp-log" do
        find("input[name=date]").set(Date.parse(date)) # Capybara formats for the browser locale
        find("input[name='measurements[][name]']", match: :first).set("pH")
        find("input[name='measurements[][value]']", match: :first).set(value)
        click_button "Log run"
      end
      assert_selector ".kbp-run", count: date == "2026-10-06" ? 1 : 2
    end

    assert_selector ".kbp-compare th[scope=row]", text: "pH"
    assert_selector ".kbp-delta", text: "+0.5"

    within(".kbp-test", text: "Fridge") { click_button "Delete test" }
    within(".app-dialog") { click_button "Delete" }
    assert_no_selector ".kbp-test-name", text: "Fridge"
    assert_not File.exist?(File.join(@kb_dir, "Cold chain", "Tests", "Fridge"))
  end
end
