module NotificationsHelper
  # Header badge: unread notifications + unfinished idea drafts waiting in the queue.
  def inbox_count(user)
    user.notifications.unread.count + user.ideas.resumable_drafts.size
  end

  # Hidden fields that say where a new task lives: { idea_id: } or { project_src:, project_path: } or {} (general).
  def task_scope_fields(scope)
    fields = Notification.scope_attributes(scope)
    safe_join(fields.map { |name, value| hidden_field_tag(name, value, id: nil) })
  end
end
