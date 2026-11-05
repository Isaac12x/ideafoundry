require "application_system_test_case"

# Real right-click on selected markdown text swaps the browser menu for the app's: Add, Expand, Ask AI, Copy.
class KbSelectionMenuSystemTest < ApplicationSystemTestCase
  PASSAGE = "Fermentation converts sugars into acid, gas or alcohol using yeast and bacteria."

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-selmenu-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    filler = (1..40).map { |i| "Filler paragraph number #{i} that only exists to make the page scroll." }.join("\n\n")
    File.write(File.join(@kb_dir, "note.md"), "# Title\n\n#{filler}\n\n#{PASSAGE}\n\n#{filler}\n")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    @user.update_local_agent_settings("enabled" => "1")
    @user.agent_runs.create!(status: :running, last_heartbeat_at: Time.current) # a live agent: the Ask Agent shell renders
    page.driver.browser.manage.window.resize_to(1280, 800)
  end

  teardown do
    @user.agent_events.delete_all
    @user.agent_runs.delete_all
    @user.kb_annotations.delete_all
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def passage_el = find(".kb-markdown p", text: PASSAGE)

  # Real triple-click selects the paragraph; then a real right-click on it. Returns after the menu is up.
  def select_and_right_click
    el = passage_el
    page.execute_script("arguments[0].scrollIntoView({block: 'center'})", el)
    page.driver.browser.action.move_to(el.native, 0, 0).double_click.perform # word
    page.driver.browser.action.move_to(el.native, 0, 0).click.click.click.perform # paragraph (triple)
    page.execute_script(<<~JS)
      window.__page = "same-document";
      window.__toolbar = [];
      const bar = document.querySelector(".kb-marker");
      document.addEventListener("contextmenu", () => {
        window.__after = true;
        new MutationObserver(() => window.__toolbar.push(!bar.hidden)).observe(bar, { attributes: true });
      }, true);
    JS
    assert_equal PASSAGE, page.evaluate_script("getSelection().toString().trim()")
    page.driver.browser.action.move_to(el.native, 0, 0).context_click.perform
    assert_selector ".kb-selection-menu", wait: 5
  end

  def item(label) = find(".kb-selection-menu button", text: label)

  def stub_supervisor(&block) = LocalAgentSupervisorJob.stub(:perform_later, nil, &block)

  test "right-click keeps the selection, replaces the native menu and does not fight the annotate toolbar" do
    visit kb_path(src: 0, file: "note.md")
    select_and_right_click
    assert_equal PASSAGE, page.evaluate_script("getSelection().toString().trim()"), "right-click lost the selection"
    assert_equal %w[Add\ highlight Expand Ask\ AI Copy], all(".kb-selection-menu button").map { |b| b.text.lines.first.strip }
    assert page.evaluate_script("document.querySelector('.kb-marker').hidden"), "annotate toolbar competes with the menu"
    assert_not_includes page.evaluate_script("window.__toolbar"), true, "annotate toolbar flashed after the right-click"
    # Escape closes and the selection is still there
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector ".kb-selection-menu"
  end

  test "Add highlights the selection and saves it" do
    visit kb_path(src: 0, file: "note.md")
    select_and_right_click
    item("Add highlight").click
    assert_selector "mark.kb-mark", wait: 5
    Timeout.timeout(5) { sleep 0.1 until @user.kb_annotations.exists? }
    assert_includes @user.kb_annotations.last.attributes.values.map(&:to_s).join(" "), "Fermentation"
  end

  test "Copy puts the selected text on the clipboard" do
    visit kb_path(src: 0, file: "note.md")
    page.driver.browser.execute_cdp("Browser.grantPermissions", permissions: %w[clipboardReadWrite clipboardSanitizedWrite], origin: page.current_url[%r{\Ahttps?://[^/]+}])
    select_and_right_click
    item("Copy").click
    clip = page.driver.browser.execute_async_script("const done = arguments[arguments.length - 1]; setTimeout(() => navigator.clipboard.readText().then(done, (e) => done('ERR ' + e)), 300)")
    assert_equal PASSAGE, clip.to_s.strip
  end

  test "Expand queues the question without reloading, keeps scroll and selection, and shows it pending" do
    visit kb_path(src: 0, file: "note.md")
    stub_supervisor do
      select_and_right_click
      y = page.evaluate_script("document.querySelector('.kb-content-area')?.scrollTop || scrollY")
      item("Expand").click
      assert_selector "#ask_agent_sidebar .ask-agent-message--pending", text: "Waiting", wait: 8
      assert_selector "#ask_agent_sidebar .ask-agent-message--user p", text: PASSAGE
      assert_equal "same-document", page.evaluate_script("window.__page"), "the page reloaded"
      assert_in_delta y, page.evaluate_script("document.querySelector('.kb-content-area')?.scrollTop || scrollY"), 2, "scroll position moved"
      assert_equal PASSAGE, page.evaluate_script("getSelection().toString().trim()"), "selection lost"
    end
    event = @user.agent_events.where(event_type: "question").last
    assert_includes event.payload["question"], "Expand on this passage (from note.md)"
    assert_includes event.payload["question"], "> #{PASSAGE}"
  end

  test "Ask AI opens the panel with the quoted passage, ready for the question" do
    visit kb_path(src: 0, file: "note.md")
    select_and_right_click
    item("Ask AI").click
    assert_selector "#ask_agent_sidebar", visible: true, wait: 5
    value = find("#global_agent_question_body").value
    assert_includes value, "About this passage (from note.md):"
    assert_includes value, "> #{PASSAGE}"
    assert_equal "global_agent_question_body", page.evaluate_script("document.activeElement.id")
  end

  test "agent turned off: Expand says so with a link to settings and sends nothing" do
    @user.update_local_agent_settings("enabled" => "0")
    visit kb_path(src: 0, file: "note.md")
    assert_no_selector "#ask-agent"
    select_and_right_click
    item("Expand").click
    assert_selector ".kb-selection-notice", text: "turned off", wait: 5
    assert_selector ".kb-selection-notice a[href='#{settings_local_agent_path}']"
    assert_equal 0, @user.agent_events.where(event_type: "question").count
  end

  def answer!(question, text)
    @user.agent_events.create!(event_type: "answer", summary: text.truncate(160), target: question, payload: { "answer" => text })
  end

  test "Expand: the answer appears in the sidebar without a reload" do
    visit kb_path(src: 0, file: "note.md")
    stub_supervisor do
      select_and_right_click
      item("Expand").click
      assert_selector "#ask_agent_sidebar .ask-agent-message--pending", wait: 8
    end
    question = @user.agent_events.where(event_type: "question").last
    answer!(question, "First paragraph.\n\nSecond paragraph <b>escaped</b>.")
    assert_selector "#ask_agent_sidebar .ask-agent-message--agent p", text: "First paragraph.", wait: 10
    assert_no_selector "#ask_agent_sidebar .ask-agent-message--pending"
    assert_includes find("#ask_agent_sidebar .ask-agent-message--agent p").text, "<b>escaped</b>"
    assert_equal "same-document", page.evaluate_script("window.__page"), "the page reloaded"
  end

  test "sidebar Send: queued without a reload, box cleared, answer appears without a reload" do
    visit kb_path(src: 0, file: "note.md")
    page.execute_script("window.__page = 'same-document'")
    find(".ask-agent-launcher").click
    stub_supervisor do
      fill_in "global_agent_question_body", with: "What is fermentation?"
      click_button "Send"
      assert_selector "#ask_agent_sidebar .ask-agent-message--user p", text: "What is fermentation?", wait: 8
      assert_selector "#ask_agent_sidebar .ask-agent-message--pending"
    end
    assert_equal "", find("#global_agent_question_body").value
    assert_equal "global_agent_question_body", page.evaluate_script("document.activeElement.id")
    answer!(@user.agent_events.where(event_type: "question").last, "Sugars to acid.")
    assert_selector "#ask_agent_sidebar .ask-agent-message--agent p", text: "Sugars to acid.", wait: 10
    assert_equal "same-document", page.evaluate_script("window.__page"), "the page reloaded"
  end

  test "agent enabled but not running: Expand lands in the sidebar, which says Not running" do
    @user.agent_runs.delete_all
    visit kb_path(src: 0, file: "note.md")
    assert_selector "#ask-agent"
    stub_supervisor do
      select_and_right_click
      item("Expand").click
      assert_selector "#ask_agent_sidebar .ask-agent-message--pending", wait: 8
    end
    assert_selector "#ask_agent_sidebar .ask-agent-sidebar__status", text: "Not running"
    assert_selector "#ask_agent_sidebar .ask-agent-sidebar__notice a[href='#{settings_local_agent_path}']"
    assert_equal 1, @user.agent_events.where(event_type: "question").count
  end

  test "agent not running: Ask AI still opens the sidebar with the passage" do
    @user.agent_runs.delete_all
    visit kb_path(src: 0, file: "note.md")
    select_and_right_click
    item("Ask AI").click
    assert_selector "#ask_agent_sidebar", visible: true, wait: 5
    assert_includes find("#global_agent_question_body").value, "> #{PASSAGE}"
  end

  test "editor: right-click on selected textarea text opens the menu; Add as quote works" do
    visit kb_edit_path(src: 0, file: "note.md")
    ta = find("form.kb-editor textarea")
    page.execute_script("const t = arguments[0]; t.value = 'Alpha beta gamma'; t.focus(); t.setSelectionRange(0, t.value.length)", ta)
    page.driver.browser.action.context_click(ta.native).perform # centre of the box: inside the selected line? the selection is wide enough only if the text is
    assert_selector ".kb-selection-menu", wait: 5
    assert_equal "Alpha beta gamma", page.evaluate_script("(() => { const t = document.querySelector('form.kb-editor textarea'); return t.value.slice(t.selectionStart, t.selectionEnd) })()"), "selection lost"
    item("Add as quote").click
    assert_equal "Alpha beta gamma\n\n> Alpha beta gamma\n", ta.value
  end
end
