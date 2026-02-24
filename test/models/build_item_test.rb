require "test_helper"

class BuildItemTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "valid with title and user" do
    item = BuildItem.new(user: @user, title: "Add dark mode")
    assert item.valid?
  end

  test "invalid without title" do
    item = BuildItem.new(user: @user, title: nil)
    assert_not item.valid?
  end

  test "invalid without user" do
    item = BuildItem.new(title: "Something")
    assert_not item.valid?
  end

  test "sets position automatically" do
    item = BuildItem.create!(user: @user, title: "First")
    assert_equal 1, item.position
    item2 = BuildItem.create!(user: @user, title: "Second")
    assert_equal 2, item2.position
  end

  test "pending scope returns incomplete items ordered by position" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 2)
    i2 = BuildItem.create!(user: @user, title: "B", position: 1)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3, completed: true, completed_at: Time.current)
    result = @user.build_items.pending
    assert_equal [i2, i1], result.to_a
  end

  test "completed scope returns done items" do
    i1 = BuildItem.create!(user: @user, title: "Done", completed: true, completed_at: Time.current)
    i2 = BuildItem.create!(user: @user, title: "Not done")
    result = @user.build_items.done
    assert_equal [i1], result.to_a
  end

  test "mark_completed! sets completed and timestamp" do
    item = BuildItem.create!(user: @user, title: "Todo")
    item.mark_completed!
    assert item.completed
    assert_not_nil item.completed_at
  end

  test "mark_pending! clears completed" do
    item = BuildItem.create!(user: @user, title: "Todo", completed: true, completed_at: Time.current)
    item.mark_pending!
    assert_not item.completed
    assert_nil item.completed_at
  end
end
