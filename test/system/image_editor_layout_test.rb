require "application_system_test_case"

class ImageEditorLayoutTest < ApplicationSystemTestCase
  setup do
    @idea = ideas(:one)
    page.driver.browser.manage.window.resize_to(900, 640)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "image editor is centered in the viewport with visible actions" do
    visit edit_idea_path(@idea)

    attach_file("idea_hero_image", Rails.root.join("public/icon.png"), make_visible: true)
    assert_selector ".image-editor", visible: true

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const modal = document.querySelector(".image-editor")
        const dialog = document.querySelector(".image-editor__dialog")
        const addButton = [...document.querySelectorAll(".image-editor__footer button")]
          .find((button) => button.textContent.trim() === "Add Image")
        const dialogRect = dialog.getBoundingClientRect()
        const buttonRect = addButton.getBoundingClientRect()

        return {
          modalParentIsBody: modal.parentElement === document.body,
          top: dialogRect.top,
          bottom: dialogRect.bottom,
          centerDelta: Math.abs((dialogRect.top + dialogRect.height / 2) - window.innerHeight / 2),
          addButtonBottom: buttonRect.bottom,
          viewportHeight: window.innerHeight
        }
      })()
    JS

    assert geometry["modalParentIsBody"], "modal should be fixed relative to the viewport"
    assert_operator geometry["top"], :>=, 0
    assert_operator geometry["bottom"], :<=, geometry["viewportHeight"]
    assert_operator geometry["addButtonBottom"], :<=, geometry["viewportHeight"]
    assert_operator geometry["centerDelta"], :<=, 4
  end
end
