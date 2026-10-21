require "application_system_test_case"

# Legacy weighted scoring lives on the edit form (data-controller="score"). The old
# score display / formula / reset / history / progress-bar UI no longer exists.
class ScoringSystemTest < ApplicationSystemTestCase
  def setup
    # The app is single-user and signs in as User.first, so own the idea as that user.
    @user = User.first
    @idea = ideas(:one)
    @idea.update!(user: @user, trl: 5, difficulty: 3, opportunity: 7, timing: 6)
  end

  test "real-time scoring interface updates value display" do
    visit edit_idea_path(@idea)

    within "[data-controller='score']" do
      assert_selector "[data-score-target='trlValue']", text: "5"
    end

    # Set the range input directly and fire the input event the controller listens to.
    page.execute_script(<<~JS)
      const slider = document.querySelector("[data-score-target='trlSlider']")
      slider.value = 8
      slider.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    within "[data-controller='score']" do
      assert_selector "[data-score-target='trlValue']", text: "8"
    end
  end

  test "scoring sliders and values are present" do
    visit edit_idea_path(@idea)

    within "[data-controller='score']" do
      %w[trl difficulty opportunity timing].each do |name|
        assert_selector "[data-score-target='#{name}Slider']"
        assert_selector "[data-score-target='#{name}Value']"
      end
    end
  end

  test "scoring tooltips provide helpful information" do
    visit edit_idea_path(@idea)

    within "[data-controller='score']" do
      assert_selector ".score-tooltip", text: "TRL"
      assert_selector ".score-tooltip", text: "Difficulty"
      assert_selector ".score-tooltip", text: "Opportunity"
      assert_selector ".score-tooltip", text: "Timing"
      assert_selector ".tooltip-text", text: "Technology Readiness Level", visible: false
      assert_selector ".tooltip-text", text: "Execution difficulty", visible: false
    end
  end
end
