require "application_system_test_case"

class IdeaHeroSystemTest < ApplicationSystemTestCase
  setup do
    @idea = ideas(:one)
    @idea.update!(user: User.first)
  end

  # Several files at once: they become pending tiles in one step, no per-file editor.
  def add_images(count)
    paths = Array.new(count) { Rails.root.join("public/icon.png").to_s }
    attach_file("idea_hero_images", paths, make_visible: true)
  end

  def font_errors
    page.driver.browser.logs.get(:browser).map(&:message).grep(/font|OTS/i)
  end

  def draw_rectangle
    find(".excalidraw .App-toolbar [data-testid='toolbar-rectangle']").click
    canvas = find(".excalidraw canvas.interactive")
    page.driver.browser.action.move_to(canvas.native, -100, -100).click_and_hold.move_by(150, 100).release.perform
  end

  test "mix images and a drawing, reorder, save, and see the composed hero" do
    visit edit_idea_path(@idea)

    add_images(2)
    assert_selector ".dropzone__preview-grid .dropzone__thumb", count: 2
    assert_no_selector ".image-editor", visible: true
    add_images(1)
    assert_selector ".dropzone__preview-grid .dropzone__thumb", count: 3 # a later drop adds, it does not replace

    click_on "Add drawing"
    # The modal must be on screen: <main> has a CSS filter that used to push fixed children off-view.
    assert_selector ".idea-drawings__modal-dialog", visible: true
    top = page.evaluate_script("document.querySelector('.idea-drawings__modal-dialog').getBoundingClientRect().top")
    assert_operator top, :>=, 0
    assert_equal "BODY", page.evaluate_script("document.querySelector('.idea-drawings__modal').parentElement.tagName")

    assert_selector ".excalidraw canvas.interactive"
    draw_rectangle
    sleep 0.3
    click_on "Done" # flushes the pending save immediately
    assert_selector ".hero-set__list .hero-item[data-drawing-id] img", wait: 10
    assert_equal 1, @idea.drawings.hero.count
    assert @idea.drawings.hero.first.rendered_png.attached?

    # Move the drawing to the front with the keyboard-accessible button.
    find(".hero-item[data-drawing-id] [aria-label='Move earlier']").click
    first_key = page.evaluate_script("document.querySelector('.hero-set__list .hero-item').dataset.heroKey")
    assert_match(/\Adrawing:/, first_key)

    find("input[type=submit][value*='Update'], input[type=submit][value*='Save'], button[type=submit]", match: :first).click
    assert_selector ".idea-hero-cap--mosaic[data-cells='4']", wait: 10
    assert_equal first_key, @idea.reload.hero_items.first.key
    assert_equal 4, @idea.hero_items.size

    # A second save with nothing new adds nothing.
    visit edit_idea_path(@idea)
    find("input[type=submit][value*='Update'], input[type=submit][value*='Save'], button[type=submit]", match: :first).click
    assert_selector ".idea-hero-cap--mosaic[data-cells='4']", wait: 10
    assert_equal 4, @idea.reload.hero_items.size
  end

  test "editor open and close latency, and re-open keeps one editor" do
    drawing = Drawing.create!(idea: @idea, title: "Seed", role: :hero, content: { "elements" => [], "appState" => {}, "files" => {} })
    visit edit_idea_path(@idea)
    click_on "Add drawing"
    assert_selector ".excalidraw canvas.interactive"
    click_on "Done"
    assert_no_selector ".idea-drawings__modal-dialog", visible: true
    3.times do
      find(".hero-item[data-drawing-id='#{drawing.id}'] [data-slot='edit']").click
      assert_selector ".idea-drawings__modal-dialog", visible: true
      sleep 0.4
      click_on "Done"
      assert_no_selector ".idea-drawings__modal-dialog", visible: true
    end
    timings = page.evaluate_script("window.__drawingTimings")
    puts "\nTIMINGS #{timings.inspect}"
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.idea-drawings__modal .excalidraw').length")
    assert_equal 1, @idea.drawings.hero.count, "opening and closing an untouched drawing creates nothing"
  end

  test "standalone drawing page mounts and saves" do
    visit new_idea_drawing_path(@idea)
    assert_selector ".excalidraw canvas.interactive"
    draw_rectangle
    find(".excalidraw-topbar button", text: "Save").click
    assert_text "Saved", wait: 10
    assert_equal 1, @idea.drawings.count
    assert_empty font_errors, "Excalidraw fonts must load from the local asset path"
  end

  test "editor still opens after a Turbo back/forward round trip" do
    visit edit_idea_path(@idea)
    click_on "Add drawing"
    assert_selector ".excalidraw canvas.interactive"
    click_on "Done"

    click_on "Ideas", match: :first # leave via Turbo, cached snapshot is taken
    assert_current_path ideas_path, ignore_query: true
    page.go_back
    assert_selector ".hero-set"
    assert_selector ".idea-drawings__modal.hidden", visible: :all # controller reconnected and portaled the modal
    # The restored snapshot carries no React DOM from the previous visit...
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.excalidraw').length")
    # ...and a fresh open works.
    click_on "Add drawing"
    assert_selector ".idea-drawings__modal-dialog", visible: true
    assert_selector ".excalidraw canvas.interactive"
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.excalidraw').length")
  end

  test "navigating away mid-edit, inside the debounce window, still persists the drawing" do
    visit edit_idea_path(@idea)
    click_on "Add drawing"
    assert_selector ".excalidraw canvas.interactive"
    draw_rectangle
    assert_equal 0, @idea.drawings.count # not auto-saved yet (2s debounce)

    page.execute_script("Turbo.visit('#{ideas_path}')") # modal still open, nothing flushed by the user
    assert_current_path ideas_path, ignore_query: true
    Timeout.timeout(10) { sleep 0.2 until @idea.drawings.hero.count == 1 && @idea.drawings.hero.first.rendered_png.attached? }

    visit edit_idea_path(@idea)
    assert_selector ".hero-item[data-drawing-id] img"
    assert_equal 1, @idea.drawings.hero.first.content["elements"].count { |e| e["type"] == "rectangle" }
  end
end
