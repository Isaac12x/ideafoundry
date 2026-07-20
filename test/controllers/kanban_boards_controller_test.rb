require "test_helper"

class KanbanBoardsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.order(:id).first
  end

  test "moves a board up by swapping positions" do
    first = @user.kanban_boards.create!(name: "First")
    second = @user.kanban_boards.create!(name: "Second")

    patch move_kanban_board_path(second, direction: "up")

    assert_redirected_to lists_path(view: "kanban")
    assert_operator second.reload.position, :<, first.reload.position
  end

  test "move at the edge is a no-op" do
    board = @user.kanban_boards.ordered.first || @user.kanban_boards.create!(name: "Only")
    position = board.position

    patch move_kanban_board_path(board, direction: "up")

    assert_equal position, board.reload.position
  end

  test "destroys a board and its columns" do
    board = @user.kanban_boards.create!(name: "Doomed")
    board.lists.create!(name: "Col", kind: :kanban, user: @user)

    assert_difference -> { @user.kanban_boards.count }, -1 do
      delete kanban_board_path(board)
    end

    assert_redirected_to lists_path(view: "kanban")
  end
end
