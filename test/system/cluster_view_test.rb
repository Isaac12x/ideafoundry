require "application_system_test_case"

class ClusterViewTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @idea1 = ideas(:one)
    @idea2 = ideas(:two)
    
    # Set some initial cluster positions
    @idea1.update(cluster_x: 100, cluster_y: 100)
    @idea2.update(cluster_x: 300, cluster_y: 200)
  end

  test "visiting the cluster view" do
    visit clusters_path
    
    assert_selector "h2", text: "Cluster View"
    assert_selector ".cluster-canvas"
    assert_selector ".cluster-idea-card", count: 2
  end

  test "cluster view displays idea cards with correct information" do
    visit clusters_path
    
    within first(".cluster-idea-card") do
      assert_selector ".idea-title"
      assert_selector ".idea-state"
      assert_selector ".drag-handle"
    end
  end

  test "cluster view has navigation links" do
    visit clusters_path
    
    assert_link "List View"
    assert_link "All Ideas"
    assert_selector "button", text: "Create Cluster"
  end

  test "zoom controls are present and functional" do
    visit clusters_path
    
    assert_selector ".zoom-controls"
    assert_selector "button", text: "+"
    assert_selector "button", text: "-"
    assert_selector "button", text: "Reset"
    assert_selector "[data-cluster-target='zoomLevel']", text: "100%"
  end

  test "view controls are present" do
    visit clusters_path
    
    assert_selector ".view-controls"
    assert_selector "button", text: "Fit All"
    assert_selector "button", text: "Center"
  end

  test "cluster creation modal functionality" do
    visit clusters_path
    
    # Click create cluster button
    click_button "Create Cluster"
    
    # Should change button text
    assert_selector "button", text: "Cancel"
    
    # Click cancel to reset
    click_button "Cancel"
    assert_selector "button", text: "Create Cluster"
  end

  test "idea cards are positioned correctly" do
    visit clusters_path
    
    idea1_card = find("[data-idea-id='#{@idea1.id}']")
    idea2_card = find("[data-idea-id='#{@idea2.id}']")
    
    # Check that cards have position styles
    assert_match /left:\s*100px/, idea1_card[:style]
    assert_match /top:\s*100px/, idea1_card[:style]
    assert_match /left:\s*300px/, idea2_card[:style]
    assert_match /top:\s*200px/, idea2_card[:style]
  end

  test "empty state is shown when no ideas exist" do
    # Remove all ideas
    Idea.destroy_all
    
    visit clusters_path
    
    assert_selector ".empty-state"
    assert_text "No ideas yet"
    assert_link "Create Idea"
  end

  test "navigation between views works" do
    visit clusters_path
    
    click_link "List View"
    assert_current_path lists_path
    assert_selector "h2", text: "My Lists"
    
    click_link "Cluster View"
    assert_current_path clusters_path
    assert_selector "h2", text: "Cluster View"
  end
end