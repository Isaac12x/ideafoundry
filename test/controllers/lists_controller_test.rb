require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.order(:id).first
    @kanban_list = @user.lists.kanban.first || @user.lists.create!(name: "Backlog")
    @idea = @user.ideas.first || @user.ideas.create!(title: "Test Idea")
  end

  test "index exposes kanban and named list views" do
    named_list = @user.lists.create!(name: "Launch Candidates", kind: :named)
    @user.update_list_settings("default_view" => "named")

    get lists_path

    assert_response :success
    assert_select "[data-tabs-default-tab-value=?]", "named"
    assert_select "[data-list-kind=?]", "named", text: /#{named_list.name}/
    assert_select "[data-list-kind=?]", "kanban", text: /#{@kanban_list.name}/
  end

  test "creates named list" do
    assert_difference -> { @user.lists.named.count }, 1 do
      post lists_path, params: { list: { name: "Investor Targets", kind: "named" } }
    end

    assert_redirected_to lists_path(view: "named")
    assert_equal "Investor Targets", @user.lists.named.order(:created_at).last.name
  end

  test "adds and removes ideas from named list" do
    named_list = @user.lists.create!(name: "Launch Candidates", kind: :named)

    assert_difference -> { named_list.idea_lists.count }, 1 do
      post add_idea_list_path(named_list), params: { idea_id: @idea.id }
    end

    assert_redirected_to list_path(named_list)

    assert_difference -> { named_list.idea_lists.count }, -1 do
      delete remove_idea_list_path(named_list), params: { idea_id: @idea.id }
    end

    assert_redirected_to list_path(named_list)
  end
end
