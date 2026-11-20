require "application_system_test_case"

# Proves lazyLoadControllersFrom breaks nothing: on every main page each [data-controller] identifier ends up
# registered with Stimulus and the browser console stays free of severe errors.
class LazyControllersSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-lazy-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    File.write(File.join(@kb_dir, "note.md"), "# Heading\n\nbody")
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment")
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [ @kb_dir ], "hide_native" => true }, "local_agent" => { "enabled" => true }
    ))
    @idea = ideas(:one).tap { |i| i.update!(user: @user) }
    Licensor.create!(idea: @idea, company: "Acme")
    @submission = Submission.create!(user: @user, title: "Sub")
    page.driver.browser.logs.get(:browser) # drain
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  MISSING_JS = <<~JS.freeze
    (() => !window.Stimulus ? ["(Stimulus not started)"] : [...new Set([...document.querySelectorAll("[data-controller]")]
      .flatMap(e => (e.getAttribute("data-controller") || "").split(/\\s+/)).filter(Boolean))]
      .filter(id => !window.Stimulus.router.modulesByIdentifier.has(id)))()
  JS

  # Polls (up to 60s under parallel load: TipTap alone is dozens of unbundled modules) until the lazy loader registered everything.
  def unregistered
    deadline = Time.now + 60
    loop do
      missing = begin
        page.evaluate_script(MISSING_JS)
      rescue Selenium::WebDriver::Error::WebDriverError # navigating
        [ "(navigating)" ]
      end
      return missing if missing.empty? || Time.now > deadline
      sleep 0.2
    end
  end

  def severe_errors
    page.driver.browser.logs.get(:browser).select { |l| l.level == "SEVERE" }
      .map(&:message).reject { |m| m =~ /favicon|Failed to load resource|net::ERR|WebSocket/i }
  end

  def check(label)
    assert_selector "body"
    warn "check #{label}" if ENV["LAZY_DEBUG"]
    assert_empty unregistered, "unregistered controllers on #{label}"
    assert_empty severe_errors, "console errors on #{label}"
  end

  # JS clicks by index: Turbo/Stimulus re-renders make held element references stale.
  def click_each(selector, label)
    n = page.all(selector, minimum: 1).size
    n.times do |i|
      page.execute_script("document.querySelectorAll(arguments[0])[arguments[1]]?.click()", selector, i)
      check "#{label} #{i}"
    end
  end

  def check_visit(path)
    visit path
    check path
  end

  test "every main page registers all its controllers without console errors" do
    [ ideas_path, idea_path(@idea), new_idea_path, edit_idea_path(@idea), kb_path,
      kb_file_path(src: 0, path: "note.md"), kb_project_path(src: 0, path: "Ferment"),
      ideas_intake_path, submission_path(@submission), licensing_crm_path, lists_path, topologies_path,
      new_topology_path, templates_path, exports_path, build_items_path, notifications_path,
      settings_path, settings_features_path, settings_display_path, settings_shortcuts_path, settings_scoring_path,
      settings_email_path, settings_security_path, settings_local_agent_path, settings_github_path,
      settings_topologies_path, settings_themes_path, settings_lists_path, settings_idea_tabs_path,
      settings_templates_path, settings_kb_path, settings_activity_path ].each { |p| check_visit(p) }
  end

  test "idea tabs and project stages" do
    visit idea_path(@idea)
    click_each("[data-tabs-target=tab]", "idea tab")
    visit kb_project_path(src: 0, path: "Ferment")
    click_each(".kbp-stage-btn", "project stage")
  end

  test "turbo drive link click, frame and stream insertion, panels" do
    visit ideas_path
    click_on @idea.title, match: :first # Turbo Drive navigation, no full reload
    assert_current_path idea_path(@idea)
    check "turbo-drive idea show"

    visit kb_path # KB file opened into the frame
    find(".kb-node", text: "note.md", match: :first).click
    assert_selector ".kb-viewer, .kb-viewer-bar, .kb-md-body, [data-controller*=kb]", wait: 10
    check "kb file in frame"

    find("details.inbox summary").click # lazy turbo-frame
    assert_no_text "Loading...", wait: 10
    check "inbox panel"

    page.driver.browser.action.key_down(:control).send_keys("k").key_up(:control).perform
    assert_selector "dialog.command-palette[open]", wait: 5
    check "command palette"
    send_keys :escape

    find("#ask-agent .ask-agent-launcher").click
    check "ask agent"
  end
end
