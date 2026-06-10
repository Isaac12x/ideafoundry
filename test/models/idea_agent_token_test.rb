require "test_helper"

class IdeaAgentTokenTest < ActiveSupport::TestCase
  setup do
    @idea = ideas(:one)
    @idea.user.update_idea_work_token_settings("enabled" => "1")
  end

  test "generate stores only a digest and authenticates active unexpired tokens" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Spec Bot")

    assert token.persisted?
    assert token.raw_token.present?
    assert_not_equal token.raw_token, token.token_digest
    assert_equal token, IdeaAgentToken.authenticate(token.raw_token)
    assert token.reload.last_used_at.present?
  end

  test "authenticate rejects inactive and expired tokens" do
    inactive = IdeaAgentToken.generate(idea: @idea, name: "Inactive")
    inactive.update!(active: false)

    expired = IdeaAgentToken.generate(idea: @idea, name: "Expired", expires_at: 1.minute.ago)

    assert_nil IdeaAgentToken.authenticate(inactive.raw_token)
    assert_nil IdeaAgentToken.authenticate(expired.raw_token)
  end

  test "authenticate rejects tokens when idea work tokens are disabled" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Spec Bot")
    @idea.user.update_idea_work_token_settings("enabled" => "0")

    assert_nil IdeaAgentToken.authenticate(token.raw_token)
  end
end
