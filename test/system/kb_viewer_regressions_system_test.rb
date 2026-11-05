require "application_system_test_case"

class KbViewerRegressionsSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-viewer-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    pages = %w[Alpha Bravo Charlie Delta].map { |word| "/Helvetica findfont 40 scalefont setfont 72 600 moveto (#{word} passage) show showpage" }
    IO.popen(%W[gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -sOutputFile=#{File.join(@kb_dir, "paper.pdf")} -], "w") { |ps| ps.write(pages.join("\n")) }
    FileUtils.cp(Rails.root.join("public", "icon.png"), File.join(@kb_dir, "pic.png"))
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_annotations.delete_all
    @user.kb_media_edits.delete_all
    FileUtils.rm_rf(@kb_dir)
  end

  test "pdf studio renders pages, and saving really edits the file" do
    visit kb_path(src: 0, file: "paper.pdf")
    assert_selector ".kb-pdf-viewer canvas", minimum: 1, wait: 20
    find("a.kb-content-edit-link[title=Edit]").click

    assert_selector ".kb-media-editor__pdf .kb-pdf-page canvas", minimum: 1, wait: 20
    top = page.evaluate_script("document.querySelector('.kb-media-editor__pdf').getBoundingClientRect().top - document.querySelector('.kb-media-editor__stage').getBoundingClientRect().top")
    assert_operator top, :>=, 0, "first page must not be clipped above the stage"

    fill_in "operations[page_sequence]", with: "1 3"
    click_button "Save edit"
    assert_selector "[data-kb-media-editor-target=status]", text: "Rendering", wait: 10
    KbMediaEditRunnerJob.perform_now(@user.kb_media_edits.last.id) # no queue runner under system tests
    assert_equal "2", `pdfinfo #{File.join(@kb_dir, "paper.pdf")}`[/Pages:\s+(\d+)/, 1]
  end

  test "edit opened by direct URL keeps the sidebar" do
    visit kb_edit_path(src: 0, file: "paper.pdf")
    assert_selector ".kb-sidebar .kb-tree"
    assert_selector ".kb-media-editor__pdf canvas", minimum: 1, wait: 20
  end

  test "markdown edit and project pages opened by direct URL keep the sidebar" do
    File.write(File.join(@kb_dir, "note.md"), "# Note")
    visit kb_edit_path(src: 0, file: "note.md")
    assert_selector ".kb-sidebar .kb-tree"
    assert_selector "form.kb-editor"

    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Lab")
    visit kb_project_path(src: 0, path: "Lab")
    assert_selector ".kb-sidebar .kb-tree"
    assert_selector "turbo-frame#kb-content", text: "Lab"
  end

  test "a highlight is a bookmark that jumps to the passage" do
    visit kb_path(src: 0, file: "paper.pdf")
    assert_selector ".kb-pdf-text span", minimum: 1, wait: 20
    span = find(".kb-pdf-page[data-page='1'] .kb-pdf-text span", match: :first)
    page.execute_script(<<~JS, span.native)
      const range = document.createRange(); range.selectNodeContents(arguments[0])
      const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range)
      arguments[0].dispatchEvent(new PointerEvent("pointerup", { bubbles: true }))
    JS
    assert_selector "[data-kb-annotate-target=toolbar]:not([hidden])"
    page.execute_script("document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'b', bubbles: true }))")

    assert_selector ".kb-bookmarks__go[data-act=highlight]", text: "Alpha passage", wait: 10
    assert_equal 1, @user.kb_annotations.count

    page.execute_script("document.querySelector('.kb-content-area').scrollTop = 0; document.querySelector('.kb-pdf-page[data-page=\"4\"]').scrollIntoView()")
    find(".kb-bookmarks__go[data-act=highlight]").click
    assert_selector "mark.kb-mark.is-active", text: "Alpha", wait: 10
    assert page.evaluate_script("(() => { const r = document.querySelector('mark.kb-mark').getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight })()")
  end

  test "toolbar has no root icon or favourite buttons, and the tree starts right under it" do
    visit kb_path(src: 0, file: "paper.pdf")
    assert_no_selector ".kb-tree-head button[aria-label='Personalise folder icon']"
    assert_no_selector ".kb-tree-head button[aria-label='Add to favourites']"
    gap = page.evaluate_script("document.querySelector('.kb-tree .kb-node').getBoundingClientRect().top - document.querySelector('.kb-sidebar-inner').getBoundingClientRect().top")
    assert_operator gap, :<=, 2
    page.save_screenshot(Rails.root.join("tmp/screenshots/kb_toolbar.png"))
  end

  test "video bar uses icons, with names for assistive tech" do
    FileUtils.touch(File.join(@kb_dir, "clip.mp4"))
    visit kb_path(src: 0, file: "clip.mp4")
    within(".kb-vplayer__bar") do
      assert_selector "button[aria-label='Play'] svg"
      assert_selector "button[aria-label='Fullscreen'] svg"
      assert_selector "button[aria-label='Save current frame as PNG'] svg"
      assert_no_text "Shot"
      assert_no_text "Full"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/kb_video_bar.png"))
  end

  test "real browser cache is emptied by a manual lock and by idle expiry" do
    @user.update_authenticator_app_settings("enabled" => "1")
    secret = @user.reload.authenticator_app_secret
    unlock = lambda do
      assert_selector "input[name=authenticator_code]", wait: 10
      fill_in "authenticator_code", with: AuthenticatorApp.code(secret)
      find("input[name=authenticator_code]").native.send_keys(:return)
      assert_no_selector "input[name=authenticator_code]", wait: 10
    end

    # fetch() of a file the page never shows: reads the HTTP cache only, not an image the page reloads itself or Blink's per-tab memory cache.
    FileUtils.cp(File.join(@kb_dir, "pic.png"), File.join(@kb_dir, "probe.png"))
    visit root_path
    unlock.call
    visit kb_path(src: 0, file: "probe.png")
    url = find("img.kb-image-preview")[:src]
    visit kb_path(src: 0, file: "pic.png")
    assert_selector "img.kb-image-preview"
    bytes = lambda do
      page.evaluate_async_script(<<~JS, url)
        const [url, done] = arguments
        performance.clearResourceTimings()
        fetch(url).then((r) => r.blob()).then(() => setTimeout(() => done(performance.getEntriesByName(url).at(-1).transferSize), 200))
      JS
    end

    bytes.call
    assert_equal 0, bytes.call, "precondition: a repeat hit comes from the HTTP cache"

    page.execute_script("document.querySelector('[data-typing-activity-target=lockForm]').requestSubmit()")
    unlock.call
    assert_selector "img.kb-image-preview", wait: 10
    assert_operator bytes.call, :>, 0, "manual lock must empty the cache"
    assert_equal 0, bytes.call

    # Idle expiry on the server, with no POST from the page (closed tab, sleeping laptop).
    travel 1.day
    visit kb_path(src: 0, file: "pic.png")
    unlock.call
    assert_selector "img.kb-image-preview", wait: 10
    assert_operator bytes.call, :>, 0, "idle expiry must empty the cache"
  end
end
