require "application_system_test_case"

class AppDialogSystemTest < ApplicationSystemTestCase
  setup do
    visit ideas_path
    page.execute_script("localStorage.removeItem('kb_notes_custom_tabs'); localStorage.removeItem('kb_note_general')")
    visit ideas_path
  end

  test "note tabs use the app dialog for adding and deleting" do
    wait_for_controller("kb-notes", "addTab")
    find(".kb-notes-add-btn").click

    assert_selector ".app-dialog[open]", visible: true
    assert_text "Add note tab"
    fill_in "Tab name", with: "Research"
    click_button "Add tab"

    assert_no_selector ".app-dialog[open]"
    assert_selector ".kb-notes-tab", text: "Research"

    find("[aria-label='Delete Research note tab']").click
    assert_selector ".app-dialog[open][data-variant='danger']", visible: true
    assert_text "Delete note tab?"
    assert_text "Delete “Research” and its saved notes?"
    within(".app-dialog") { click_button "Cancel" }
    assert_no_selector ".app-dialog[open]"
    assert_selector ".kb-notes-tab", text: "Research"

    find("[aria-label='Delete Research note tab']").click
    within(".app-dialog") { click_button "Delete tab" }
    assert_no_selector ".kb-notes-tab", text: "Research"
  end

  test "Turbo confirmations use the app dialog" do
    page.execute_script("setTimeout(() => window.Turbo.config.forms.confirm('Delete this item?'), 0)")

    assert_selector ".app-dialog[open][data-variant='danger']", visible: true
    assert_text "Confirm change"
    assert_text "Delete this item?"
    within(".app-dialog") { click_button "Cancel" }
    assert_no_selector ".app-dialog[open]"
  end

  private

  def wait_for_controller(identifier, method)
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script(<<~JS.squish) == "function"
        typeof window.Stimulus
          ?.getControllerForElementAndIdentifier(document.body, #{identifier.to_json})
          ?.[#{method.to_json}]
      JS
    end
  end
end
