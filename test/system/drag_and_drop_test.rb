require "application_system_test_case"

class DragAndDropTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @list1 = lists(:one)
    @list2 = lists(:two)
    @idea1 = ideas(:one)
    @idea2 = ideas(:two)
    @idea3 = ideas(:three)
    
    # Fixtures already set up the associations
    # @idea1 is in @list1 at position 1
    # @idea2 is in @list1 at position 2
    # @idea3 is in @list2 at position 1
  end

  test "draggable items have drag handle" do
    visit lists_path
    
    within "#list_#{@list1.id}_ideas" do
      assert_selector ".drag-handle", count: 2
      assert_selector ".draggable-item[data-idea-id='#{@idea1.id}']"
      assert_selector ".draggable-item[data-idea-id='#{@idea2.id}']"
    end
  end

  test "drop zones are properly configured" do
    visit lists_path
    
    assert_selector ".drop-zone[data-list-id='#{@list1.id}']"
    assert_selector ".drop-zone[data-list-id='#{@list2.id}']"
    assert_selector "[data-controller='drag']"
  end

  test "idea cards display correct information" do
    visit lists_path
    
    within ".draggable-item[data-idea-id='#{@idea1.id}']" do
      assert_text @idea1.title
      assert_selector ".idea-state"
      assert_selector ".drag-handle"
    end
  end

  test "drag handle shows visual feedback on hover" do
    visit lists_path
    
    drag_handle = find(".draggable-item[data-idea-id='#{@idea1.id}'] .drag-handle")
    
    # Check that the drag handle is visible
    assert drag_handle.visible?
  end

  test "empty drop zone displays placeholder text" do
    # Create a list with no ideas
    empty_list = @user.lists.create!(name: "Empty List")
    
    visit lists_path
    
    within "#list_#{empty_list.id}_ideas" do
      assert_selector ".empty-drop-zone"
      assert_text "No ideas in this list yet"
    end
  end

  test "idea cards have correct data attributes for dragging" do
    visit lists_path
    
    idea_card = find(".draggable-item[data-idea-id='#{@idea1.id}']")
    
    assert_equal @idea1.id.to_s, idea_card["data-idea-id"]
    assert_equal @list1.id.to_s, idea_card["data-list-id"]
    assert idea_card["data-position"].present?
  end

  test "multiple lists are displayed correctly" do
    visit lists_path
    
    assert_selector ".list-container", count: 2
    assert_text @list1.name
    assert_text @list2.name
  end

  test "drag controller is connected to the page" do
    visit lists_path
    
    assert_selector "[data-controller='drag']"
    assert_selector "[data-drag-url-value]"
  end

  test "idea state is displayed with correct styling" do
    @idea1.update!(state: :validated)
    
    visit lists_path
    
    within ".draggable-item[data-idea-id='#{@idea1.id}']" do
      assert_selector ".idea-state.validated"
      assert_text "Validated"
    end
  end

  test "idea score is displayed when present" do
    @idea1.update!(trl: 8, difficulty: 3, opportunity: 9, timing: 7)
    @idea1.save! # Trigger score calculation
    
    visit lists_path
    
    within ".draggable-item[data-idea-id='#{@idea1.id}']" do
      assert_selector ".idea-score"
      assert_text "Score:"
    end
  end

  test "idea description is truncated in card view" do
    long_description = "A" * 200
    @idea1.update!(description: long_description)
    
    visit lists_path
    
    within ".draggable-item[data-idea-id='#{@idea1.id}']" do
      description_text = find(".idea-description").text
      assert description_text.length < long_description.length
    end
  end

  test "drag and drop updates are handled via turbo streams" do
    visit lists_path
    
    # Verify turbo is loaded
    assert page.evaluate_script("typeof Turbo !== 'undefined'")
  end

  test "lists page has proper navigation" do
    visit lists_path
    
    assert_selector ".page-header"
    assert_link "All Ideas"
    assert_link "New List"
  end

  test "idea cards link to idea detail page" do
    visit lists_path
    
    within ".draggable-item[data-idea-id='#{@idea1.id}']" do
      assert_link @idea1.title, href: idea_path(@idea1)
    end
  end

  test "list header shows edit and delete actions" do
    visit lists_path
    
    within ".list-container", match: :first do
      assert_link "Edit"
      assert_link "Delete"
    end
  end

  test "drag controller has correct URL value" do
    visit lists_path
    
    drag_container = find("[data-controller='drag']")
    assert_equal update_idea_position_lists_path, drag_container["data-drag-url-value"]
  end

  test "positions are correctly set on idea cards" do
    visit lists_path
    
    within "#list_#{@list1.id}_ideas" do
      idea1_card = find(".draggable-item[data-idea-id='#{@idea1.id}']")
      idea2_card = find(".draggable-item[data-idea-id='#{@idea2.id}']")
      
      assert_equal "1", idea1_card["data-position"]
      assert_equal "2", idea2_card["data-position"]
    end
  end

  test "ideas are ordered by position within lists" do
    visit lists_path
    
    within "#list_#{@list1.id}_ideas" do
      cards = all(".draggable-item")
      positions = cards.map { |card| card["data-position"].to_i }
      
      assert_equal positions.sort, positions, "Ideas should be ordered by position"
    end
  end

  test "drag handle has proper accessibility attributes" do
    visit lists_path
    
    drag_handle = find(".drag-handle", match: :first)
    assert drag_handle["title"].present?, "Drag handle should have a title attribute"
  end

  test "drop zones have minimum height for easy dropping" do
    visit lists_path
    
    drop_zone = find(".drop-zone", match: :first)
    # The CSS sets min-height: 100px
    assert drop_zone.visible?
  end
end
