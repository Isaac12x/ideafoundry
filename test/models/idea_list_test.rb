require "test_helper"

class IdeaListTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    # Use a fresh list with no fixture data
    @list = List.create!(user: @user, name: "Test List")
    # Use a fresh idea not in any list
    @idea = Idea.create!(user: @user, title: "Unassigned Idea")
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

  test "should not allow idea in multiple kanban lists by default" do
    @idea_list.save!

    other_list = List.create!(user: @user, name: "Other List")
    duplicate = IdeaList.new(idea: @idea, list: other_list)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idea_id], "already has a kanban list"
  end

  test "should allow idea in one kanban list and multiple named lists" do
    @idea_list.save!
    shortlist = List.create!(user: @user, name: "Shortlist", kind: :named)
    launch = List.create!(user: @user, name: "Launch", kind: :named)

    assert_difference -> { @idea.idea_lists.count }, 2 do
      IdeaList.create!(idea: @idea, list: shortlist)
      IdeaList.create!(idea: @idea, list: launch)
    end
  end

  test "should not allow idea in multiple kanban lists" do
    @idea_list.save!
    other_column = List.create!(user: @user, name: "Other Column", kind: :kanban)

    duplicate = IdeaList.new(idea: @idea, list: other_column)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idea_id], "already has a kanban list"
  end

  test "should not allow duplicate idea in same named list" do
    named_list = List.create!(user: @user, name: "Shortlist", kind: :named)
    IdeaList.create!(idea: @idea, list: named_list)

    duplicate = IdeaList.new(idea: @idea, list: named_list)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idea_id], "is already in this list"
  end

  test "should not allow duplicate idea in same list" do
    @idea_list.save!

    duplicate = IdeaList.new(idea: @idea, list: @list)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idea_id], "is already in this list"
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

  test "should allow list to contain multiple ideas" do
    idea2 = Idea.create!(user: @user, title: "Second Idea")

    IdeaList.create!(idea: @idea, list: @list)
    IdeaList.create!(idea: idea2, list: @list)

    assert_equal 2, @list.idea_lists.count
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
