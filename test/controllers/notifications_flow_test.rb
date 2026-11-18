require "test_helper"

class NotificationsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first
    @idea = @user.ideas.create!(title: "Host", state: :idea_new)
  end

  test "notify! supports general, idea and project scopes" do
    g = Notification.notify!(title: "G")
    i = Notification.notify!(scope: @idea, title: "I")
    p = Notification.notify!(scope: { src: 1, path: "proj" }, title: "P")
    assert_equal [ g ], Notification.general.to_a
    assert_equal [ i ], Notification.in_scope_kind("idea").to_a
    assert_equal [ p ], Notification.for_project("1", "proj").to_a
  end

  test "inbox lists items, marks read, completes a task" do
    n = Notification.notify!(title: "Ping")
    get notifications_path
    assert_response :success
    assert_select ".inbox-title", text: "Ping"

    patch notification_path(n)
    assert n.reload.read?

    post tasks_path, params: { title: "Do it" }
    task = TodoItem.find_by!(title: "Do it")
    assert_nil task.idea_id
    patch toggle_task_path(task)
    assert task.reload.completed?
  end

  test "project task is scoped" do
    post tasks_path, params: { title: "T", project_src: "2", project_path: "a/b" }
    assert_equal 1, TodoItem.for_project("2", "a/b").count
  end

  test "empty drafts are not resumable and are purged by new" do
    blank = @user.ideas.create!(draft: true, state: :idea_new)
    kept = @user.ideas.create!(draft: true, state: :idea_new, title: "Keep me")
    assert_equal [ kept ], @user.ideas.resumable_drafts
    get new_idea_path
    assert_nil Idea.find_by(id: blank.id)
    assert Idea.find_by(id: kept.id)
  end

  test "edit form of a draft has no resume prompt" do
    d = @user.ideas.create!(draft: true, state: :idea_new, title: "x")
    get edit_idea_path(d, draft: 1)
    assert_select ".idea-draft-resume", false
  end
end
