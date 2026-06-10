require "application_system_test_case"

class NapkinCalculationsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.create!(title: "Sys napkin", state: :idea_new, attempt_count: 0)
  end

  test "user enters napkin formula and it persists and renders on show" do
    visit edit_idea_path(@idea)

    find(".napkin-header").click
    assert_selector ".napkin-grid-table", visible: true

    enter_cell("A1", "Users")
    enter_cell("B1", "1000")
    enter_cell("A2", "ARPU")
    enter_cell("B2", "50")
    enter_cell("A3", "Revenue")
    enter_cell("B3", "=B1*B2")

    click_button "Update Idea"

    @idea.reload
    assert_equal "1000", @idea.napkin_calculations["cells"]["B1"]["raw"]
    assert_equal "=B1*B2", @idea.napkin_calculations["cells"]["B3"]["raw"]

    visit idea_path(@idea)
    assert_selector ".napkin-readonly"
    within ".napkin-grid--readonly" do
      assert_text "Users"
      assert_text "Revenue"
      assert_text "50000"
    end
  end

  private

  def enter_cell(ref, value)
    cell = find(".napkin-cell[data-ref='#{ref}']")
    cell.double_click
    input = cell.find("input")
    input.fill_in with: value
    input.send_keys :enter
  end
end
