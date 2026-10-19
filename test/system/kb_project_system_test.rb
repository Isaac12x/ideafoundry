require "application_system_test_case"

class KbProjectSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-project-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "create a project, add a test, log two runs and compare them" do
    visit kb_path
    find(".kb-folder-header", match: :first).right_click
    find("[data-menu-item=newProject]").click

    find(".kb-node.is-naming .kb-node-name-input").send_keys([ :command, "a" ], "Cold chain", :enter)
    assert_selector ".kb-project-link", text: "Cold chain"
    assert Kb::Project.at(@kb_dir, "Cold chain")

    find(".kb-project-link", text: "Cold chain").click
    assert_selector ".kbp-title", text: "Cold chain"

    find(".kbp-stage-btn", text: "Test").click # test mode: Tests lead, cards open
    assert_selector "#kbp-sec-tests.is-open"
    find(".kbp-edit--inline summary").click
    find("input[name=name]").set("Fridge")
    click_button "Add test"
    assert_selector ".kbp-test-name", text: "Fridge"

    [ [ "2026-10-06", "4.0" ], [ "2026-10-20", "4.5" ] ].each do |date, value|
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

    # findings: one field + Enter, edit in place
    find(".kbp-test .kbp-finding-add input").send_keys("Holds at 4C", :enter)
    assert_selector ".kbp-finding-text", text: "Holds at 4C"
    find(".kbp-finding").hover
    find(".kbp-finding-tools button", text: "Edit").click
    find(".kbp-finding-edit textarea").send_keys(" for 3 weeks", :enter)
    assert_selector ".kbp-finding-text", text: "Holds at 4C for 3 weeks"

    # collapse state survives the Turbo re-render
    find("#kbp-sec-materials .kbp-sec-toggle").click
    find("#kbp-sec-findings .kbp-sec-toggle").click
    assert_no_selector "#kbp-sec-findings .kbp-sec-body", visible: :visible
    find(".kbp-test select[name=verdict] + button").click
    find(".select-menu-option", text: "Supported").click
    assert_selector ".kbp-test .kbp-verdict[data-tone=success]"
    assert_no_selector "#kbp-sec-findings .kbp-sec-body", visible: :visible

    within(".kbp-test", text: "Fridge") { click_button "Delete test" }
    within(".app-dialog") { click_button "Delete" }
    assert_no_selector ".kbp-test-name", text: "Fridge"
    assert_not File.exist?(File.join(@kb_dir, "Cold chain", "Tests", "Fridge"))
  end

  test "dragging a file onto a role shelf in the tree re-roles it" do
    project = Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Lab")
    File.write(File.join(project.abs, "a.txt"), "x")
    visit kb_path(src: 0, project: "Lab")
    assert_selector ".kb-role-group--inbox .kb-file-row[data-kb-tree-rel-param='Lab/a.txt']"
    assert_no_selector ".kb-role-group--output", visible: :visible # empty shelves are hidden until a drag

    page.execute_script(<<~JS)
      const fire = (el, type, dt) => el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }))
      const dt = new DataTransfer()
      fire(document.querySelector(".kb-file-row[data-kb-tree-rel-param='Lab/a.txt']"), "dragstart", dt)
      window.__dragDt = dt
    JS
    assert_selector ".kb-role-group--output", visible: :visible # shelf appears while dragging
    page.execute_script(<<~JS)
      const header = document.querySelector(".kb-role-group--output .kb-role-header")
      header.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: window.__dragDt }))
      window.__over = header.classList.contains("is-drop-target")
      header.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: window.__dragDt }))
    JS
    assert page.evaluate_script("window.__over"), "header highlights as a drop target"
    assert_selector ".kb-role-group--output .kb-file-row[data-kb-tree-rel-param='Lab/a.txt']", visible: :all # Output shelf starts collapsed
    assert_equal "output", Kb::Project.at(@kb_dir, "Lab").material("a.txt")["role"]
  end
end
