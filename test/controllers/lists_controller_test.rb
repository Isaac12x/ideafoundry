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

  test "index groups kanban columns by board" do
    board = @user.kanban_boards.create!(name: "Validation")
    @user.lists.create!(name: "Validate", kind: :kanban, kanban_board: board)

    get lists_path

    assert_response :success
    assert_select "[data-kanban-board-id=?]", board.id.to_s, text: /Validation/
    assert_select "[data-kanban-board-id=?] [data-list-kind=?]", board.id.to_s, "kanban", text: /Validate/
  end

  test "creates kanban board" do
    assert_difference -> { @user.kanban_boards.count }, 1 do
      post kanban_boards_path, params: { kanban_board: { name: "Validation" } }
    end

    assert_redirected_to lists_path(view: "kanban")
    assert_equal "Validation", @user.kanban_boards.order(:created_at).last.name
  end

  test "creates kanban column on selected board" do
    board = @user.kanban_boards.create!(name: "Validation")

    assert_difference -> { board.lists.count }, 1 do
      post lists_path, params: { list: { name: "Validate", kind: "kanban", kanban_board_id: board.id } }
    end

    assert_redirected_to lists_path(view: "kanban")
    assert_equal board, @user.lists.kanban.order(:created_at).last.kanban_board
  end

  test "kanban cards show idea and kanban move timestamps" do
    @kanban_list.idea_lists.find_or_create_by!(idea: @idea)

    get lists_path

    assert_response :success
    assert_select ".idea-card", text: /Updated/
    assert_select ".idea-card", text: /Moved/
  end

  test "moving an idea on one board preserves its membership on another board" do
    default_board = @kanban_list.kanban_board
    target_column = @user.lists.create!(name: "Done", kind: :kanban, kanban_board: default_board)
    other_board = @user.kanban_boards.create!(name: "Validation")
    other_column = @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: other_board)

    @idea.idea_lists.destroy_all
    @idea.idea_lists.create!(list: @kanban_list)
    other_membership = @idea.idea_lists.create!(list: other_column)

    patch update_idea_position_lists_path,
      params: { idea_id: @idea.id, list_id: target_column.id, position: 1 },
      as: :json

    assert_response :success
    assert_equal target_column, @idea.idea_lists.joins(:list).find_by(lists: { kanban_board_id: default_board.id }).list
    assert_equal other_membership, @idea.idea_lists.find_by(list: other_column)
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
