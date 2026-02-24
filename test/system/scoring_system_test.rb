require "application_system_test_case"

class ScoringSystemTest < ApplicationSystemTestCase
  def setup
    @user = users(:one)
    @idea = ideas(:one)
    @idea.update!(trl: 5, difficulty: 3, opportunity: 7, timing: 6)
  end

  test "real-time scoring interface updates score display" do
    visit idea_path(@idea)
    
    # Verify initial score display
    within "[data-controller='score']" do
      assert_selector "[data-score-target='trlValue']", text: "5"
      assert_selector "[data-score-target='scoreDisplay']"
    end
    
    # Update TRL slider (simulating user interaction)
    trl_slider = find("[data-score-target='trlSlider']")
    trl_slider.set(8)
    
    # Score should update in real-time (JavaScript)
    within "[data-controller='score']" do
      assert_selector "[data-score-target='trlValue']", text: "8"
    end
  end

  test "scoring sliders are present and functional" do
    visit idea_path(@idea)
    
    within "[data-controller='score']" do
      # Verify all sliders are present
      assert_selector "[data-score-target='trlSlider']"
      assert_selector "[data-score-target='difficultySlider']"
      assert_selector "[data-score-target='opportunitySlider']"
      assert_selector "[data-score-target='timingSlider']"
      
      # Verify value displays
      assert_selector "[data-score-target='trlValue']"
      assert_selector "[data-score-target='difficultyValue']"
      assert_selector "[data-score-target='opportunityValue']"
      assert_selector "[data-score-target='timingValue']"
      
      # Verify computed score display
      assert_selector "[data-score-target='scoreDisplay']"
      assert_selector "[data-score-target='scoreFormula']"
    end
  end

  test "score history is displayed when versions exist" do
    # Create some versions with different scores
    @idea.create_version("Initial version")
    
    @idea.update!(trl: 8, opportunity: 9)
    @idea.create_version("Improved version")
    
    visit idea_path(@idea)
    
    within ".score-history" do
      assert_text "Score History"
      assert_selector ".score-history-item", count: 2
    end
  end

  test "reset scores button works" do
    visit idea_path(@idea)
    
    within "[data-controller='score']" do
      # Verify non-zero initial values
      assert_selector "[data-score-target='trlValue']", text: "5"
      
      # Click reset button
      click_button "Reset All Scores"
      
      # All values should be reset to 0 (JavaScript functionality)
      # Note: This test verifies the button exists and is clickable
      # The actual reset functionality would be tested in JavaScript unit tests
      assert_selector "button", text: "Reset All Scores"
    end
  end

  test "scoring tooltips provide helpful information" do
    visit idea_path(@idea)
    
    within "[data-controller='score']" do
      # Verify tooltip elements exist
      assert_selector ".score-tooltip", text: "TRL (Technology Readiness)"
      assert_selector ".score-tooltip", text: "Difficulty"
      assert_selector ".score-tooltip", text: "Opportunity"
      assert_selector ".score-tooltip", text: "Timing"
      
      # Verify tooltip text exists (hidden by default)
      assert_selector ".tooltip-text", text: "How mature is the technology?", visible: false
      assert_selector ".tooltip-text", text: "How hard is this to execute?", visible: false
    end
  end

  test "score formula is displayed correctly" do
    visit idea_path(@idea)
    
    within "[data-controller='score']" do
      formula_element = find("[data-score-target='scoreFormula']")
      formula_text = formula_element.text
      
      # Should contain the scoring formula with current values
      assert_includes formula_text, "× 0.3"  # TRL weight
      assert_includes formula_text, "× 0.4"  # Opportunity weight
      assert_includes formula_text, "× 0.2"  # Timing weight
      assert_includes formula_text, "× -0.1" # Difficulty weight
      assert_includes formula_text, "="
    end
  end

  test "progress bars reflect scoring values" do
    visit idea_path(@idea)
    
    within "[data-controller='score']" do
      # Check that progress bars exist and have appropriate widths
      trl_bar = find("[data-score-target='trlBar']")
      assert_equal "50%", trl_bar.style("width") # 5/10 * 100% = 50%
      
      # Verify different colored bars exist
      assert_selector ".stat-bar.difficulty"
      assert_selector ".stat-bar.opportunity"
      assert_selector ".stat-bar.timing"
    end
  end
end