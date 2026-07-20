class KanbanBoardsController < ApplicationController
  before_action :set_user

  def create
    @kanban_board = @user.kanban_boards.build(kanban_board_params)

    if @kanban_board.save
      redirect_to lists_path(view: "kanban"), notice: "Kanban board was successfully created."
    else
      redirect_to lists_path(view: "kanban"), alert: @kanban_board.errors.full_messages.to_sentence
    end
  end

  def destroy
    board = @user.kanban_boards.find(params[:id])
    board.destroy
    redirect_to lists_path(view: "kanban"), notice: "Board \"#{board.name}\" deleted."
  end

  def move
    board = @user.kanban_boards.find(params[:id])
    boards = @user.kanban_boards.ordered.to_a
    index = boards.index(board)
    other_index = params[:direction] == "up" ? index - 1 : index + 1

    if other_index.between?(0, boards.size - 1)
      other = boards[other_index]
      # position is unique per user, so swap through a temp value
      KanbanBoard.transaction do
        a = board.position
        b = other.position
        board.update_columns(position: -1)
        other.update_columns(position: a)
        board.update_columns(position: b)
      end
    end

    redirect_to lists_path(view: "kanban")
  end

  private

  def kanban_board_params
    params.require(:kanban_board).permit(:name)
  end
end
