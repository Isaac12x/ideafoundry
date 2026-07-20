require "test_helper"

class IdeaEntriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @user.update_idea_tab_settings({ "tool" => "1", "competitor" => "1", "potential_competitor" => "1" })
    @idea = @user.ideas.create!(title: "Structured Entry Test")
  end

  test "creates structured entry and returns detail and listing turbo updates" do
    assert_difference("IdeaEntry.count", 1) do
      post idea_idea_entries_path(@idea, format: :turbo_stream), params: {
        idea_entry: {
          kind: "tool",
          name: "Rails",
          url: "https://rubyonrails.org",
          description: "Framework"
        }
      }
    end

    assert_response :success
    @idea.reload
    assert_equal "Rails", @idea.idea_entries.last.name
    assert_match "idea_entries_tab_#{@idea.id}_tool", response.body
    assert_match "idea_entry_summary_#{@idea.id}_tool", response.body
    assert_match "Rails", response.body
  end

  test "shows validation errors in turbo response without creating an entry" do
    assert_no_difference("IdeaEntry.count") do
      post idea_idea_entries_path(@idea, format: :turbo_stream), params: {
        idea_entry: {
          kind: "tool",
          name: ""
        }
      }
    end

    assert_response :unprocessable_content
    assert_match "Name can", response.body
    assert_match "idea_entries_tab_#{@idea.id}_tool", response.body
    assert_match "idea_entry_summary_#{@idea.id}_tool", response.body
  end

  test "ideas index shows inline structured entry summaries for kinds with entries" do
    # Cards render read-only summaries (no quick-add form), and only for
    # kinds that already have entries.
    @idea.idea_entries.create!(kind: "tool", name: "Rails")

    get ideas_path

    assert_response :success
    assert_select "#idea_entry_summary_#{@idea.id}_tool"
    assert_select "#idea_entry_summary_#{@idea.id}_competitor", false
    assert_select "form[action='#{idea_idea_entries_path(@idea)}']", false
  end

  test "lists index hides structured entry controls on kanban cards" do
    list = @user.lists.create!(name: "Structured Entries")
    @idea.idea_lists.create!(list: list, position: 1)

    get lists_path

    assert_response :success
    assert_select "#idea_entry_summary_#{@idea.id}_tool", false
    assert_select "#idea_entry_summary_#{@idea.id}_competitor", false
    assert_select "#idea_entry_summary_#{@idea.id}_potential_competitor", false
    assert_select "form[action='#{idea_idea_entries_path(@idea)}']", false
  end

  test "topology idea listings show inline structured entry summaries" do
    # Cards render read-only summaries (no quick-add form).
    @idea.idea_entries.create!(kind: "tool", name: "Rails")
    topology = @user.topologies.create!(name: "Structured Entries #{SecureRandom.hex(4)}", topology_type: :custom)
    @idea.idea_topologies.create!(topology: topology)

    get topology_path(topology)

    assert_response :success
    assert_select "#idea_entry_summary_#{@idea.id}_tool"
    assert_select "form[action='#{idea_idea_entries_path(@idea)}']", false
  ensure
    topology&.destroy
  end
end
