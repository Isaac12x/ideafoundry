require "test_helper"

class KanbanBoardTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "sets position automatically within user" do
    board = KanbanBoard.create!(user: @user, name: "Validation")

    assert_equal @user.kanban_boards.maximum(:position), board.position
  end

  test "requires unique position per user" do
    board = KanbanBoard.create!(user: @user, name: "Validation", position: 10)
    duplicate = KanbanBoard.new(user: @user, name: "Duplicate", position: board.position)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end
end
