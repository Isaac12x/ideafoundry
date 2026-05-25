require "test_helper"

class AgentRecommendationTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user.update!(settings: {})
    @user.update_local_agent_settings("enabled" => "1", "destructive_actions_enabled" => "0")
  end

  test "approve applies through local agent tools and records review state" do
    submission = @user.submissions.create!(title: "Needs rejection", body: "Duplicate")
    recommendation = @user.agent_recommendations.create!(
      target: submission,
      action: "reject_submission",
      risk_level: "high",
      reasoning: "Duplicate of a stronger submission",
      payload: {
        "submission_id" => submission.id,
        "review_notes" => "Duplicate of a stronger submission"
      }
    )

    assert recommendation.approve!

    assert submission.reload.rejected?
    assert recommendation.reload.applied?
    assert_not_nil recommendation.reviewed_at
  end

  test "dismiss keeps the audit trail without applying the action" do
    idea = @user.ideas.create!(title: "Keep this idea", state: :triage)
    recommendation = @user.agent_recommendations.create!(
      target: idea,
      action: "transition_idea",
      risk_level: "high",
      reasoning: "Ship it",
      payload: {
        "idea_id" => idea.id,
        "state" => "shipped"
      }
    )

    assert recommendation.dismiss!

    assert idea.reload.triage?
    assert recommendation.reload.dismissed?
    assert_not_nil recommendation.reviewed_at
  end
end
