require "test_helper"

class IdeaAgentTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first
    @idea = @user.ideas.create!(title: "Agent Token Idea", state: :idea_new)
  end

  test "creates an idea token and flashes the raw token once" do
    assert_difference -> { @idea.idea_agent_tokens.count }, 1 do
      post idea_agent_tokens_url(@idea), params: { idea_agent_token: { name: "Harness" } }
    end

    assert_redirected_to idea_url(@idea)
    assert flash[:idea_agent_token].present?
    assert_equal @idea.id, flash[:idea_agent_token_idea_id]
  end

  test "destroys an idea token" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Harness")

    assert_difference -> { @idea.idea_agent_tokens.count }, -1 do
      delete idea_agent_token_url(@idea, token)
    end

    assert_redirected_to idea_url(@idea)
  end
end
