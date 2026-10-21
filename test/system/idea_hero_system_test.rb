require "application_system_test_case"

class IdeaHeroSystemTest < ApplicationSystemTestCase
  setup do
    @idea = ideas(:one)
    @idea.update!(user: User.first)
  end

  def add_image
    attach_file("idea_hero_images", Rails.root.join("public/icon.png"), make_visible: true)
    click_on "Add Image"
  end

  def draw_rectangle
    find(".excalidraw .App-toolbar [data-testid='toolbar-rectangle']").click
    canvas = find(".excalidraw canvas.interactive")
    page.driver.browser.action.move_to(canvas.native, -100, -100).click_and_hold.move_by(150, 100).release.perform
  end

  test "mix images and a drawing, reorder, save, and see the composed hero" do
    visit edit_idea_path(@idea)

    add_image
    add_image
    assert_selector ".dropzone__preview-grid .dropzone__thumb", count: 2 # second drop did not replace the first

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

    click_on "Save", match: :first rescue find("input[type=submit], button[type=submit]", match: :first).click
    assert_selector ".idea-hero-cap--mosaic[data-count='3']", wait: 10
    assert_equal first_key, @idea.reload.hero_items.first.key
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
    assert_equal 0, @idea.drawings.hero.count - 1 # opening/closing untouched drawings created nothing extra
  end

  test "standalone drawing page mounts and saves" do
    visit new_idea_drawing_path(@idea)
    assert_selector ".excalidraw canvas.interactive"
    draw_rectangle
    find(".excalidraw-topbar button", text: "Save").click
    assert_text "Saved", wait: 10
    assert_equal 1, @idea.drawings.count
  end
end
