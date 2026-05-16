require "test_helper"

class IdeaAgentTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first
    @idea = @user.ideas.create!(title: "Agent Token Idea", state: :idea_new)
    @user.update_idea_work_token_settings("enabled" => "1")
  end

  test "creates a single idea token and flashes the raw token once" do
    assert_difference -> { @idea.idea_agent_tokens.count }, 1 do
      post idea_agent_tokens_url(@idea)
    end

    assert_redirected_to idea_url(@idea)
    assert flash[:idea_agent_token].present?
    assert_equal @idea.id, flash[:idea_agent_token_idea_id]
  end

  test "rotating an idea token keeps only one token for the idea" do
    IdeaAgentToken.generate(idea: @idea, name: "Old")

    assert_no_difference -> { @idea.idea_agent_tokens.count } do
      post idea_agent_tokens_url(@idea)
    end

    assert_redirected_to idea_url(@idea)
    assert_equal 1, @idea.idea_agent_tokens.reload.count
    assert_equal "Idea agent", @idea.idea_agent_tokens.first.name
  end

  test "does not create an idea token when disabled in settings" do
    @user.update_idea_work_token_settings("enabled" => "0")

    assert_no_difference -> { @idea.idea_agent_tokens.count } do
      post idea_agent_tokens_url(@idea)
    end

    assert_redirected_to idea_url(@idea)
    assert_match(/disabled/, flash[:alert])
  end

  test "downloads agent skill markdown for an idea" do
    get "/ideas/#{@idea.id}/agent-skill.md"

    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/# Idea Foundry Idea Work/, response.body)
    assert_match(/GET \/api\/v1\/ideas\/#{@idea.id}\/document/, response.body)
    assert_match(/Authorization: Bearer/, response.body)
  end

  test "destroys an idea token" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Harness")

    assert_difference -> { @idea.idea_agent_tokens.count }, -1 do
      delete idea_agent_token_url(@idea, token)
    end

    assert_redirected_to idea_url(@idea)
  end
end
