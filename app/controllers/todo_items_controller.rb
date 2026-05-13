class TodoItemsController < ApplicationController
  before_action :set_user
  before_action :set_idea
  before_action :set_todo_item, only: [:toggle, :destroy]

  def create
    @todo_item = @idea.todo_items.build(todo_item_params)

    if @todo_item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to idea_path(@idea, anchor: "todo") }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_content }
        format.html { redirect_to idea_path(@idea, anchor: "todo"), alert: @todo_item.errors.full_messages.join(", ") }
      end
    end
  end

  def toggle
    if @todo_item.completed?
      @todo_item.mark_pending!
    else
      @todo_item.mark_completed!
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to idea_path(@idea, anchor: "todo") }
    end
  end

  def destroy
    @todo_item.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to idea_path(@idea, anchor: "todo") }
    end
  end

  def reorder
    order = Array(params[:order]).map(&:to_i).first(200)
    ActiveRecord::Base.transaction do
      order.each_with_index do |id, index|
        @idea.todo_items.where(id: id).update_all(position: index + 1)
      end
    end
    @idea.record_history!("Reordered todos", automatic: true)

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json { head :ok }
    end
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_todo_item
    @todo_item = @idea.todo_items.find(params[:id])
  end

  def todo_item_params
    params.require(:todo_item).permit(:title)
  end
end
