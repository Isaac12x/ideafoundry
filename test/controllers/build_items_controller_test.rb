require "test_helper"

class BuildItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # ApplicationController#set_user uses User.first, which returns the user
    # with the lowest primary key. With fixtures, that's users(:two).
    @user = User.first
    @previous_backlog_enabled = Rails.application.config.x.backlog_enabled
    Rails.application.config.x.backlog_enabled = true
  end

  def teardown
    Rails.application.config.x.backlog_enabled = @previous_backlog_enabled
  end

  test "GET index" do
    BuildItem.create!(user: @user, title: "Item 1")
    get build_items_path
    assert_response :success
    assert_select ".backlog-item", 1
  end

  test "POST create with valid params" do
    assert_difference("BuildItem.count", 1) do
      post build_items_path, params: { build_item: { title: "New item" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "POST create with blank title" do
    assert_no_difference("BuildItem.count") do
      post build_items_path, params: { build_item: { title: "" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "PATCH update" do
    item = BuildItem.create!(user: @user, title: "Old")
    patch build_item_path(item), params: { build_item: { title: "New" } }, as: :turbo_stream
    assert_response :success
    assert_equal "New", item.reload.title
  end

  test "PATCH update keeps the rendered item at its current backlog index" do
    BuildItem.create!(user: @user, title: "First", position: 1)
    item = BuildItem.create!(user: @user, title: "Second", position: 2)

    patch build_item_path(item), params: { build_item: { title: "Updated second" } }, as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "backlog-index"
    assert_includes @response.body, ">2</span>"
  end

  test "GET cancel edit replaces the edit form with the same backlog item" do
    item = BuildItem.create!(user: @user, title: "Cancel me")

    get cancel_edit_build_item_path(item), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "build_item_#{item.id}"
    assert_includes @response.body, "Cancel me"
  end

  test "DELETE destroy" do
    item = BuildItem.create!(user: @user, title: "Delete me")
    assert_difference("BuildItem.count", -1) do
      delete build_item_path(item), as: :turbo_stream
    end
    assert_response :success
  end

  test "DELETE destroy refreshes counters and empty state" do
    item = BuildItem.create!(user: @user, title: "Only item")

    delete build_item_path(item), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "backlog_queued_count"
    assert_includes @response.body, ">0</span>"
    assert_includes @response.body, "build_items_empty"
  end

  test "PATCH toggle marks complete" do
    item = BuildItem.create!(user: @user, title: "Toggle me")
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert item.reload.completed
  end

  test "PATCH toggle marks pending" do
    item = BuildItem.create!(user: @user, title: "Toggle me", completed: true, completed_at: Time.current)
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert_not item.reload.completed
  end

  test "PATCH toggle does not mark complete while checklist items remain" do
    item = BuildItem.create!(user: @user, title: "Toggle me", description: "- [ ] Subtask")

    patch toggle_build_item_path(item), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_not item.reload.completed
  end

  test "PATCH toggle checklist item flips a checklist line" do
    item = BuildItem.create!(user: @user, title: "Grouped", description: "- [ ] Subtask")

    patch toggle_checklist_item_build_item_path(item, line: 0), as: :turbo_stream

    assert_response :success
    assert_includes item.reload.description, "- [x] Subtask"
    assert_includes @response.body, "(0/1)"
  end

  test "PATCH reorder updates positions" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 1)
    i2 = BuildItem.create!(user: @user, title: "B", position: 2)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3)
    patch reorder_build_items_path, params: { order: [i3.id, i1.id, i2.id] }, as: :turbo_stream
    assert_response :success
    assert_equal 1, i3.reload.position
    assert_equal 2, i1.reload.position
    assert_equal 3, i2.reload.position
  end

  test "GET index redirects when backlog is disabled" do
    Rails.application.config.x.backlog_enabled = false

    get build_items_path

    assert_redirected_to root_path
    assert_equal "Backlog is not enabled.", flash[:alert]
  end
end
