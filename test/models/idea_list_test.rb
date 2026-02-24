require "test_helper"

class IdeaListTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @idea = ideas(:two)  # Use idea two which isn't connected to list one
    @list = lists(:two)  # Use list two which isn't connected to idea two
    @idea_list = IdeaList.new(idea: @idea, list: @list)
  end

  test "should be valid with valid attributes" do
    assert @idea_list.valid?
  end

  test "should require idea" do
    @idea_list.idea = nil
    assert_not @idea_list.valid?
    assert_includes @idea_list.errors[:idea], "must exist"
  end

  test "should require list" do
    @idea_list.list = nil
    assert_not @idea_list.valid?
    assert_includes @idea_list.errors[:list], "must exist"
  end

  test "should set position automatically on create" do
    @idea_list.save!
    assert_equal 1, @idea_list.position
    
    second_idea = Idea.create!(user: @user, title: "Second Idea")
    second_idea_list = IdeaList.create!(idea: second_idea, list: @list)
    assert_equal 2, second_idea_list.position
  end

  test "should require unique idea per list" do
    # Use the existing fixture relationship
    existing_idea = ideas(:one)
    existing_list = lists(:one)
    
    duplicate = IdeaList.new(idea: existing_idea, list: existing_list)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idea_id], "has already been taken"
  end

  test "should allow same idea in different lists" do
    @idea_list.save!
    
    other_list = List.create!(user: @user, name: "Other List")
    other_idea_list = IdeaList.new(idea: @idea, list: other_list)
    assert other_idea_list.valid?
  end

  test "should have ordered scope" do
    @idea_list.position = 2
    @idea_list.save!
    
    second_idea = Idea.create!(user: @user, title: "Second Idea")
    second_idea_list = IdeaList.create!(idea: second_idea, list: @list, position: 1)
    
    ordered = @list.idea_lists.ordered
    assert_equal second_idea_list, ordered.first
    assert_equal @idea_list, ordered.second
  end

  # CRUD operation tests (Requirement 1.4)
  test "should create idea_list with valid attributes" do
    idea_list = IdeaList.create!(idea: @idea, list: @list)
    
    assert idea_list.persisted?
    assert_equal @idea.id, idea_list.idea_id
    assert_equal @list.id, idea_list.list_id
    assert idea_list.position.present?
  end

  test "should read idea_list attributes" do
    idea_list = IdeaList.create!(idea: @idea, list: @list)
    retrieved = IdeaList.find(idea_list.id)
    
    assert_equal idea_list.idea_id, retrieved.idea_id
    assert_equal idea_list.list_id, retrieved.list_id
    assert_equal idea_list.position, retrieved.position
  end

  test "should update idea_list position" do
    idea_list = IdeaList.create!(idea: @idea, list: @list, position: 1)
    idea_list.update!(position: 5)
    
    idea_list.reload
    assert_equal 5, idea_list.position
  end

  test "should delete idea_list" do
    idea_list = IdeaList.create!(idea: @idea, list: @list)
    idea_list_id = idea_list.id
    
    idea_list.destroy
    assert_raises(ActiveRecord::RecordNotFound) do
      IdeaList.find(idea_list_id)
    end
  end

  # Many-to-many relationship tests (Requirement 1.4)
  test "should allow idea to be in multiple lists" do
    # Create a fresh idea not in any lists yet
    fresh_idea = Idea.create!(user: @user, title: "Fresh Idea")
    list2 = List.create!(user: @user, name: "Second List")
    
    IdeaList.create!(idea: fresh_idea, list: @list)
    IdeaList.create!(idea: fresh_idea, list: list2)
    
    fresh_idea.reload
    assert_equal 2, fresh_idea.lists.count
    assert_includes fresh_idea.lists, @list
    assert_includes fresh_idea.lists, list2
  end

  test "should allow list to contain multiple ideas" do
    idea2 = Idea.create!(user: @user, title: "Second Idea")
    
    IdeaList.create!(idea: @idea, list: @list)
    IdeaList.create!(idea: idea2, list: @list)
    
    assert_equal 2, @list.ideas.count
    assert_includes @list.ideas, @idea
    assert_includes @list.ideas, idea2
  end

  test "should maintain separate positions per list" do
    list2 = List.create!(user: @user, name: "Second List")
    
    idea_list1 = IdeaList.create!(idea: @idea, list: @list, position: 3)
    idea_list2 = IdeaList.create!(idea: @idea, list: list2, position: 1)
    
    assert_equal 3, idea_list1.position
    assert_equal 1, idea_list2.position
  end

  test "should auto-increment position within same list" do
    idea2 = Idea.create!(user: @user, title: "Second Idea")
    idea3 = Idea.create!(user: @user, title: "Third Idea")
    
    il1 = IdeaList.create!(idea: @idea, list: @list)
    il2 = IdeaList.create!(idea: idea2, list: @list)
    il3 = IdeaList.create!(idea: idea3, list: @list)
    
    assert_equal 1, il1.position
    assert_equal 2, il2.position
    assert_equal 3, il3.position
  end
end
