class NotificationsController < ApplicationController
  before_action :set_user

  # Header inbox panel (a lazy Turbo Frame): notifications, open tasks, unfinished drafts. ?kind=all|general|idea|project
  def index
    @kind = %w[general idea project].include?(params[:kind]) ? params[:kind] : "all"
    @notifications = @user.notifications.in_scope_kind(@kind).recent.limit(30)
    @tasks = TodoItem.visible_to(@user).pending.in_scope_kind(@kind).limit(50)
    @drafts = @kind == "all" || @kind == "idea" ? @user.ideas.resumable_drafts(limit: 10) : []
  end

  def update
    @user.notifications.find(params[:id]).mark_read!
    back
  end

  def read_all
    @user.notifications.unread.update_all(read_at: Time.current)
    back
  end

  def destroy
    @user.notifications.find(params[:id]).destroy
    back
  end

  private

  def back
    redirect_to url_from(params[:return_to]) || notifications_path
  end
end
