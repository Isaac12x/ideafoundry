require "application_system_test_case"

# The bottom notes + shortcuts bar must stay on screen, clickable and above KB content on every KB view.
class KbNotesBarSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-notes-bar-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    File.write(File.join(@kb_dir, "a.md"), "# hi")
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    # The browser outlives the test: put back the window size and the storage this test changed.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    begin
      page.execute_script("localStorage.clear()")
    rescue Selenium::WebDriver::Error::WebDriverError
      nil # not on an app page
    end
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def assert_bar_usable(clear: true)
    assert_selector ".kb-notes-tab-strip"
    probe = <<~JS
      (() => {
        const s = document.querySelector(".kb-notes-tab-strip"), r = s.getBoundingClientRect();
        const t = document.querySelector(".shortcuts-toggle").getBoundingClientRect();
        const on = (x, y) => !!document.elementFromPoint(x, y)?.closest(".app-notes-bar");
        return { inView: r.bottom <= window.innerHeight + 1 && r.top >= 0 && r.height > 0,
                 clear: !#{clear} || ["#main-content", ".kb-sidebar"].every((q) => { const e = document.querySelector(q); return !e || e.getBoundingClientRect().bottom <= r.top + 1 }),
                 onTop: on(r.left + r.width / 2, r.top + r.height / 2) && on(t.left + t.width / 2, t.top + t.height / 2) };
      })()
    JS
    result = page.evaluate_script(probe)
    assert result["inView"], "notes bar is off screen"
    assert result["clear"], "KB content runs beneath the notes bar"
    assert result["onTop"], "notes bar is covered"
  end

  test "bar is visible and on top on KB index, file and project views" do
    page.driver.browser.manage.window.resize_to(1280, 700)
    File.binwrite(File.join(@kb_dir, "v.mp4"), "x")
    visit kb_path
    assert_bar_usable
    visit kb_file_path(src: 0, file: "v.mp4")
    assert_bar_usable
    FileUtils.cp(Rails.root.join("public", "icon.png"), File.join(@kb_dir, "e.png"))
    visit kb_path(src: 0, file: "e.png")
    assert_bar_usable
    click_link "Edit"
    assert_selector "form.kb-media-editor"
    assert_bar_usable
    visit kb_file_path(src: 0, file: "a.md")
    assert_bar_usable
    visit kb_project_path(src: 0, path: "Ferment")
    assert_bar_usable
    assert_selector ".kb-notes-tab"
    find(".kb-notes-tab", match: :first).click
    assert_selector "body.kb-notes-expanded .kb-notes-panel-overlay"
    assert page.evaluate_script(%(document.elementFromPoint(innerWidth / 2, innerHeight - 100)?.closest(".kb-notes-panel-overlay") !== null)), "panel is under KB content"
  end

  # Where the saved state is untrusted (localStorage is user-editable, and older versions wrote other shapes).
  test "corrupt saved note tabs never empty the bar" do
    visit kb_path
    [ "null", "{}", "[null]", "[1,2]", "5", %("x"), "{{{", %([{"id":1}]) ].each do |bad|
      page.execute_script("localStorage.setItem('kb_notes_custom_tabs', arguments[0])", bad)
      visit kb_path
      assert_selector ".kb-notes-tab", text: "General", wait: 5
      assert_bar_usable
    end
  end

  test "many long note tabs keep the bar in view and the shortcut toggle reachable" do
    visit kb_path
    tabs = (1..60).map { |i| { id: "custom_#{i}", label: "A very long tab label number #{i} #{'x' * 100}" } }
    page.execute_script("localStorage.setItem('kb_notes_custom_tabs', arguments[0])", tabs.to_json)
    [ [ 1280, 700 ], [ 480, 600 ] ].each do |w, h|
      page.driver.browser.manage.window.resize_to(w, h)
      visit kb_path
      assert_selector ".kb-notes-tab", minimum: 2
      assert page.evaluate_script("(() => { const t = document.querySelector(\".kb-notes-tabs\"); return t.scrollWidth > t.clientWidth && getComputedStyle(t).overflowX === \"auto\" })()"), "clipped tabs are unreachable (list does not scroll)"
      assert_bar_usable
      find(".shortcuts-toggle").click
      assert_selector ".shortcuts-panel", visible: true
      find(".shortcuts-toggle").click
    end
  end

  test "floating widgets stand above the bar, never over its right end" do
    @user.update!(settings: @user.settings.merge("upgrade" => { "latest_version" => "99.0.0", "severity" => "minor", "release_body" => "x" * 300 }))
    page.driver.browser.manage.window.resize_to(1000, 700)
    visit kb_path
    assert_selector ".upgrade-toast--visible"
    # The Ask Agent orb only renders while an agent run is live; its CSS applies to the class alone.
    page.execute_script("const o = document.createElement('button'); o.className = 'ask-agent-launcher'; document.body.append(o)")
    overlaps = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector(".kb-notes-tab-strip").getBoundingClientRect();
        return [".ask-agent-launcher", ".upgrade-toast--visible"].filter((q) => document.querySelector(q)).map((q) => {
          const r = document.querySelector(q).getBoundingClientRect();
          return [q, r.bottom <= bar.top + 0.5];
        });
      })()
    JS
    overlaps.each { |q, clear| assert clear, "#{q} covers the notes bar" }
    assert_bar_usable
  end

  test "contrast filter, quote banner and small windows keep the bar" do
    @user.update!(settings: @user.settings.merge("display_contrast" => "150", "display_quote" => { "text" => "A long quote. " * 40 },
                                                 "quotes" => { "pages" => { "kb" => "default" } }))
    [ [ 1280, 700 ], [ 900, 320 ], [ 600, 600 ] ].each do |w, h|
      page.driver.browser.manage.window.resize_to(w, h)
      visit kb_file_path(src: 0, file: "a.md")
      assert_selector ".app-quote-banner"
      begin
        assert_bar_usable
      rescue Minitest::Assertion => e
        flunk "#{w}x#{h}: #{e.message} #{page.evaluate_script("[innerHeight, document.querySelector('.app-header').offsetHeight, document.querySelector('.app-quote-banner').offsetHeight, document.querySelector('#main-content').getBoundingClientRect().bottom, document.querySelector('.kb-notes-tab-strip').getBoundingClientRect().top]")}"
      end
    end
  end

  test "bar stays on pages that are not the KB too" do
    visit root_path
    assert_bar_usable(clear: false)
    visit new_idea_path
    assert_bar_usable(clear: false)
  end

  test "document viewers rendered as a full page keep the bar" do
    docs = File.join(@kb_dir, "docs")
    FileUtils.mkdir_p(docs)
    File.binwrite(File.join(docs, "a.pdf"), "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 300]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF")
    File.write(File.join(docs, "d.excalidraw"), { type: "excalidraw", version: 2, elements: [], appState: {} }.to_json)
    File.write(File.join(docs, "e.mmd"), "graph TD; A-->B")
    FileUtils.cp(Rails.root.join("public", "icon.png"), File.join(docs, "e.png"))
    %w[a.pdf d.excalidraw e.mmd e.png].each do |f|
      visit kb_file_path(src: 0, file: "docs/#{f}")
      assert_selector "#kb-content", wait: 10
      sleep 0.4
      assert_bar_usable
    end
  end

  test "dragging the bar opens and resizes the notes panel instead of hiding it" do
    visit kb_path
    panel = -> { page.evaluate_script("(() => { const r = document.querySelector('.kb-notes-panel-overlay').getBoundingClientRect(); return [document.body.classList.contains('kb-notes-expanded'), Math.round(r.height)] })()") }
    drag = ->(selector, dy) { page.driver.browser.action.move_to(find(selector, visible: :all).native).click_and_hold.move_by(0, dy).release.perform; sleep 0.4 }

    drag.(".kb-notes-tab-strip", -400)
    open, height = panel.()
    assert open, "dragging the collapsed bar should open the panel"
    assert_in_delta 400, height, 30

    drag.(".kb-notes-grip", 150)
    open, height = panel.()
    assert open, "dragging the panel edge should keep it open"
    assert_in_delta 250, height, 30

    find(".kb-notes-tab-strip").click # a plain click still collapses
    assert_not panel.().first
  end
end
