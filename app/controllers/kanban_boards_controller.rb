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

  private

  def kanban_board_params
    params.require(:kanban_board).permit(:name)
  end
end
