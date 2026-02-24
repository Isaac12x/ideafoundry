require "test_helper"

class IdeasControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use the same user that the controller will use (User.first)
    @user = User.first
    # Create an idea that belongs to this user
    @idea = @user.ideas.create!(
      title: "Test Idea",
      state: :idea_new,
      category: "Test"
    )
  end

  test "should get index" do
    get ideas_url
    assert_response :success
  end

  test "should get new" do
    get new_idea_url
    assert_response :success
  end

  test "should create idea" do
    assert_difference("Idea.count") do
      post ideas_url, params: { idea: { title: "New Idea", category: "Test" } }
    end

    assert_redirected_to idea_url(Idea.last)
  end

  test "should show idea" do
    get idea_url(@idea)
    assert_response :success
  end

  test "should get edit" do
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "should update idea" do
    patch idea_url(@idea), params: { idea: { title: "Updated Title" } }
    assert_redirected_to idea_url(@idea)
    
    @idea.reload
    assert_equal "Updated Title", @idea.title
  end

  test "should destroy idea" do
    assert_difference("Idea.count", -1) do
      delete idea_url(@idea)
    end

    assert_redirected_to ideas_url
  end

  # Cool-off period validation tests (Requirement 3.4)
  test "should not allow editing idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    get edit_idea_url(@idea)
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
  end

  test "should not allow updating idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    patch idea_url(@idea), params: { idea: { title: "Should Not Update" } }
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
    
    @idea.reload
    assert_not_equal "Should Not Update", @idea.title
  end

  test "should allow editing idea after cool-off period expires" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.ago)
    
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "should allow editing idea not in cool-off period" do
    @idea.update!(state: :triage, cool_off_until: nil)
    
    get edit_idea_url(@idea)
    assert_response :success
  end
end
