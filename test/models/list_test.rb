require "test_helper"

class ListTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @list = List.new(user: @user, name: "Test List")
  end

  test "should be valid with valid attributes" do
    assert @list.valid?
  end

  test "should require name" do
    @list.name = nil
    assert_not @list.valid?
    assert_includes @list.errors[:name], "can't be blank"
  end

  test "should require user" do
    @list.user = nil
    assert_not @list.valid?
    assert_includes @list.errors[:user], "must exist"
  end

  test "should set position automatically on create" do
    @list.save!
    assert_equal 3, @list.position  # User one already has positions 1 and 2 from fixtures
    
    second_list = List.create!(user: @user, name: "Second List")
    assert_equal 4, second_list.position
  end

  test "should require unique position per user" do
    @list.position = 3  # Use position 3 since 1 and 2 are taken by fixtures
    @list.save!
    
    duplicate_list = List.new(user: @user, name: "Duplicate", position: 3)
    assert_not duplicate_list.valid?
    assert_includes duplicate_list.errors[:position], "has already been taken"
  end

  test "should allow same position for different users" do
    @list.position = 3  # Use position 3 for user one
    @list.save!
    
    other_user = User.create!(email: "other@example.com", name: "Other User")
    other_list = List.new(user: other_user, name: "Other List", position: 3)  # Same position but different user
    assert other_list.valid?
  end

  test "should have many idea_lists" do
    assert_respond_to @list, :idea_lists
  end

  test "should have many ideas through idea_lists" do
    assert_respond_to @list, :ideas
  end

  test "should order idea_lists by position" do
    @list.save!
    idea1 = Idea.create!(user: @user, title: "Idea 1")
    idea2 = Idea.create!(user: @user, title: "Idea 2")
    
    @list.idea_lists.create!(idea: idea1, position: 2)
    @list.idea_lists.create!(idea: idea2, position: 1)
    
    assert_equal idea2, @list.idea_lists.first.idea
    assert_equal idea1, @list.idea_lists.second.idea
  end

  test "should have ordered scope" do
    list1 = List.create!(user: @user, name: "List 1", position: 4)
    list2 = List.create!(user: @user, name: "List 2", position: 3)
    
    ordered_lists = @user.lists.ordered
    # Check that the newly created lists are in the right order relative to each other
    user_lists = ordered_lists.where(name: ["List 1", "List 2"])
    assert_equal list2, user_lists.first
    assert_equal list1, user_lists.second
  end

  # CRUD operation tests (Requirement 1.2)
  test "should create list with valid attributes" do
    list = List.create!(user: @user, name: "New List")
    
    assert list.persisted?
    assert_equal "New List", list.name
    assert list.position.present?
  end

  test "should read list attributes" do
    list = List.create!(user: @user, name: "Test Read")
    retrieved_list = List.find(list.id)
    
    assert_equal list.name, retrieved_list.name
    assert_equal list.user_id, retrieved_list.user_id
    assert_equal list.position, retrieved_list.position
  end

  test "should update list attributes" do
    list = List.create!(user: @user, name: "Original Name")
    list.update!(name: "Updated Name")
    
    list.reload
    assert_equal "Updated Name", list.name
  end

  test "should delete list" do
    list = List.create!(user: @user, name: "To Delete")
    list_id = list.id
    
    list.destroy
    assert_raises(ActiveRecord::RecordNotFound) do
      List.find(list_id)
    end
  end

  # Relationship tests (Requirement 1.4)
  test "should contain multiple ideas" do
    list = List.create!(user: @user, name: "Multi-idea List")
    idea1 = Idea.create!(user: @user, title: "Idea 1")
    idea2 = Idea.create!(user: @user, title: "Idea 2")
    
    list.ideas << idea1
    list.ideas << idea2
    
    assert_equal 2, list.ideas.count
    assert_includes list.ideas, idea1
    assert_includes list.ideas, idea2
  end

  test "should cascade delete idea_lists when list is deleted" do
    list = List.create!(user: @user, name: "Test Cascade")
    idea = Idea.create!(user: @user, title: "Test Idea")
    idea_list = IdeaList.create!(idea: idea, list: list)
    
    idea_list_id = idea_list.id
    list.destroy
    
    assert_raises(ActiveRecord::RecordNotFound) do
      IdeaList.find(idea_list_id)
    end
  end

  test "should maintain position ordering across multiple lists" do
    list1 = List.create!(user: @user, name: "List A")
    list2 = List.create!(user: @user, name: "List B")
    list3 = List.create!(user: @user, name: "List C")
    
    ordered = @user.lists.ordered.where(name: ["List A", "List B", "List C"])
    assert_equal [list1, list2, list3], ordered.to_a
  end
end
