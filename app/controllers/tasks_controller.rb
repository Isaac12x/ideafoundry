# General and per-project tasks (idea tasks keep using TodoItemsController); the panel can also toggle any task.
class TasksController < ApplicationController
  before_action :set_user

  def create
    attrs = { idea_id: nil }
    if params[:idea_id].present?
      attrs[:idea_id] = @user.ideas.find(params[:idea_id]).id
    elsif params[:project_path].present?
      attrs.merge!(project_src: params[:project_src].to_s, project_path: params[:project_path].to_s, user: @user)
    else
      attrs[:user] = @user
    end
    task = TodoItem.new(attrs.merge(title: params[:title].to_s.squish))
    flash[:alert] = task.errors.full_messages.to_sentence unless task.save
    back
  end

  def toggle
    task = find_task
    task.completed? ? task.mark_pending! : task.mark_completed!
    back
  end

  def destroy
    find_task.destroy
    back
  end

  private

  def find_task
    TodoItem.visible_to(@user).find(params[:id])
  end

  def back
    redirect_to url_from(params[:return_to]) || notifications_path
  end
end
