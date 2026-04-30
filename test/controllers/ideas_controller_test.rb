require "test_helper"

class IdeasControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use the same user that the controller will use (User.first)
    @user = User.first
    # Create an idea that belongs to this user
    @idea = @user.ideas.create!(
      title: "Test Idea",
      state: :idea_new
    )
  end

  test "should get index" do
    get ideas_url
    assert_response :success
  end

  test "should get new (auto-drafts and redirects to edit)" do
    assert_difference("Idea.where(draft: true).count", 1) do
      get new_idea_url
    end
    draft = Idea.where(draft: true).order(:created_at).last
    assert_redirected_to edit_idea_url(draft, draft: 1)
  end

  test "drafts are excluded from index" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    get ideas_url
    assert_response :success
    assert_no_match draft.title, response.body
  end

  test "drafts are excluded from search" do
    @user.ideas.create!(title: "DraftSearchable", state: :idea_new, draft: true)
    get search_ideas_url(q: "DraftSearchable")
    assert_response :success
    json = JSON.parse(response.body)
    assert_empty json["results"]
  end

  test "updating a draft promotes it to a real idea" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    patch idea_url(draft), params: { idea: { title: "Promoted" } }
    draft.reload
    refute draft.draft?
    assert_equal "Promoted", draft.title
  end

  test "should create idea" do
    assert_difference("Idea.count") do
      post ideas_url, params: { idea: { title: "New Idea" } }
    end

    assert_redirected_to idea_url(Idea.last)
  end

  test "should show idea" do
    get idea_url(@idea)
    assert_response :success
  end

  test "should get edit" do
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "should update idea" do
    patch idea_url(@idea), params: { idea: { title: "Updated Title" } }
    assert_redirected_to idea_url(@idea)
    
    @idea.reload
    assert_equal "Updated Title", @idea.title
  end

  test "should destroy idea" do
    assert_difference("Idea.count", -1) do
      delete idea_url(@idea)
    end

    assert_redirected_to ideas_url
  end

  # Cool-off period validation tests (Requirement 3.4)
  test "should not allow editing idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    get edit_idea_url(@idea)
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
  end

  test "should not allow updating idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    patch idea_url(@idea), params: { idea: { title: "Should Not Update" } }
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
    
    @idea.reload
    assert_not_equal "Should Not Update", @idea.title
  end

  test "should allow editing idea after cool-off period expires" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.ago)
    
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "should allow editing idea not in cool-off period" do
    @idea.update!(state: :triage, cool_off_until: nil)
    
    get edit_idea_url(@idea)
    assert_response :success
  end

  # Archive / Restore tests
  test "should archive idea" do
    post archive_idea_url(@idea)
    assert_redirected_to ideas_url

    @idea.reload
    assert @idea.archived?
    assert @idea.discarded_at.present?
  end

  test "should restore archived idea" do
    @idea.update!(discarded_at: Time.current)

    post restore_idea_url(@idea)
    assert_redirected_to idea_url(@idea)

    @idea.reload
    refute @idea.archived?
    assert_nil @idea.discarded_at
  end

  test "should show archived ideas page" do
    @idea.update!(discarded_at: Time.current)

    get archived_ideas_url
    assert_response :success
  end

  test "archived ideas are excluded from index by default" do
    @idea.update!(discarded_at: Time.current)

    get ideas_url
    assert_response :success
    # The archived idea should not appear in the response body
    assert_no_match @idea.title, response.body
  end

  # Search tests
  test "search endpoint returns JSON results" do
    get search_ideas_url(q: @idea.title)
    assert_response :success

    json = JSON.parse(response.body)
    assert json["results"].is_a?(Array)
  end

  test "search finds ideas by title" do
    get search_ideas_url(q: "Test Idea")
    assert_response :success

    json = JSON.parse(response.body)
    assert json["results"].any? { |r| r["id"] == @idea.id }
  end

  test "search returns empty for blank query" do
    get search_ideas_url(q: "")
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal [], json["results"]
  end

  # Enrichment tests
  test "enrich action enqueues job" do
    assert_enqueued_with(job: IdeaEnrichmentJob) do
      post enrich_idea_url(@idea)
    end

    assert_redirected_to idea_url(@idea)
  end

  test "enrichment_status returns JSON" do
    get enrichment_status_idea_url(@idea)
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @idea.id, json["idea_id"]
    assert json.key?("enriched")
  end
end
