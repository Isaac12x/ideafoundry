require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Zebrafish tracker")
    @idea.notes.create!(body: "remember the zebrafish tank")
    @user.topologies.create!(name: "Zebra tools", topology_type: :custom)
  end

  test "groups hits by type and skips empty groups" do
    get global_search_path, params: { q: "zebra" }
    groups = response.parsed_body["groups"].to_h { |g| [ g["label"], g["items"] ] }
    assert_equal [ "Ideas", "Notes", "Topologies" ], groups.keys
    assert_equal idea_path(@idea), groups["Ideas"].first["url"]
  end

  test "finds a description-only draft and titles it from the description" do
    draft = @user.ideas.create!(draft: true, title: "", description: "<div>Quokka sanctuary pitch<br>more</div>", state: :idea_new)
    get global_search_path, params: { q: "quokka" }
    groups = response.parsed_body["groups"].to_h { |g| [ g["label"], g["items"] ] }
    assert_equal "Quokka sanctuary pitch", groups["Drafts"].first["title"]
    assert_equal edit_idea_path(draft, draft: 1), groups["Drafts"].first["url"]
  end

  test "blank query returns nothing" do
    get global_search_path, params: { q: " " }
    assert_equal [], response.parsed_body["groups"]
  end
end
