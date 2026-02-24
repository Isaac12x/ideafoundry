require "test_helper"

class BuildItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # ApplicationController#set_user uses User.first, which returns the user
    # with the lowest primary key. With fixtures, that's users(:two).
    @user = User.first
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

  test "DELETE destroy" do
    item = BuildItem.create!(user: @user, title: "Delete me")
    assert_difference("BuildItem.count", -1) do
      delete build_item_path(item), as: :turbo_stream
    end
    assert_response :success
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
end
