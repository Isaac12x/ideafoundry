require "test_helper"

class LocalAgent::ToolboxTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user.update!(settings: {})
    @idea = @user.ideas.create!(
      title: "Local Agent Target",
      state: :idea_new,
      description: "Thin starting description"
    )
  end

  test "mutating tools reject writes while local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")

    assert_no_difference "Note.count" do
      result = toolbox.call("create_note", {
        "idea_id" => @idea.id,
        "body" => "Add context from the local agent"
      })

      assert_equal false, result.fetch(:ok)
      assert_equal "local_agent_disabled", result.fetch(:error)
    end
  end

  test "destructive tools create recommendations when destructive autonomy is disabled" do
    @user.update_local_agent_settings("enabled" => "1", "destructive_actions_enabled" => "0")
    submission = @user.submissions.create!(title: "Duplicate submission", body: "Already covered")

    assert_difference "AgentRecommendation.count", 1 do
      result = toolbox.call("reject_submission", {
        "submission_id" => submission.id,
        "review_notes" => "Duplicate of an existing idea",
        "reasoning" => "The payload appears to duplicate current work."
      })

      assert_equal true, result.fetch(:ok)
      assert_equal "recommended", result.fetch(:status)
      assert result.fetch(:recommendation_id)
    end

    assert submission.reload.pending?
    recommendation = AgentRecommendation.order(:created_at).last
    assert_equal @user, recommendation.user
    assert_equal "Submission", recommendation.target_type
    assert_equal submission.id, recommendation.target_id
    assert_equal "reject_submission", recommendation.action
    assert_equal "high", recommendation.risk_level
    assert_equal "pending", recommendation.status
    assert_equal "Duplicate of an existing idea", recommendation.payload["review_notes"]
  end

  test "destructive tools apply directly when destructive autonomy is enabled" do
    @user.update_local_agent_settings("enabled" => "1", "destructive_actions_enabled" => "1")
    submission = @user.submissions.create!(title: "Reject directly", body: "No longer useful")

    assert_no_difference "AgentRecommendation.count" do
      result = toolbox.call("reject_submission", {
        "submission_id" => submission.id,
        "review_notes" => "Outside the current product direction"
      })

      assert_equal true, result.fetch(:ok)
      assert_equal "rejected", result.dig(:submission, :status)
    end

    assert submission.reload.rejected?
    assert_equal "Outside the current product direction", submission.review_notes
  end

  test "idea updates create a single normal history version" do
    @user.update_local_agent_settings("enabled" => "1")

    assert_difference -> { @idea.versions.count }, 1 do
      result = toolbox.call("update_idea", {
        "idea_id" => @idea.id,
        "description" => "A stronger local-agent description.",
        "commit_message" => "Local agent: improve description"
      })

      assert_equal true, result.fetch(:ok)
    end

    @idea.reload
    assert_equal "A stronger local-agent description.", @idea.description.to_plain_text.strip
    assert_equal "Local agent: improve description", @idea.latest_version.commit_message
  end

  test "list work returns prioritized candidates across app surfaces" do
    @user.update_local_agent_settings("enabled" => "1")
    submission = @user.submissions.create!(title: "High priority intake", priority: :high)
    build_item = @user.build_items.create!(title: "Stale build detail", description: "- [ ] Fill in acceptance criteria")

    result = toolbox.call("list_work")

    assert_equal true, result.fetch(:ok)
    work = result.fetch(:work)
    assert work.any? { |item| item[:target_type] == "Submission" && item[:target_id] == submission.id }
    assert work.any? { |item| item[:target_type] == "Idea" && item[:target_id] == @idea.id }
    assert work.any? { |item| item[:target_type] == "BuildItem" && item[:target_id] == build_item.id }
  end

  test "list work prioritizes unanswered local agent questions" do
    @user.update_local_agent_settings("enabled" => "1")
    question = @user.agent_events.create!(
      event_type: "question",
      summary: "What should I focus on next?",
      payload: { "question" => "What should I focus on next?" }
    )

    result = toolbox.call("list_work", { "limit" => 1 })

    assert_equal true, result.fetch(:ok)
    work = result.fetch(:work)
    assert_equal "AgentEvent", work.first[:target_type]
    assert_equal question.id, work.first[:target_id]
    assert_equal "User", work.first.dig(:payload, :context_record, :record_type)
    assert_equal @user.id, work.first.dig(:payload, :context_record, :record_id)
  end

  test "read record supports user database context" do
    @user.update_local_agent_settings("enabled" => "1")
    @user.facts.create!(body: "Focus follows validated demand.")

    result = toolbox.call("read_record", {
      "record_type" => "User",
      "record_id" => @user.id
    })

    assert_equal true, result.fetch(:ok)
    record = result.fetch(:record)
    assert_equal "User", record[:target_type]
    assert record[:ideas].any? { |idea| idea[:id] == @idea.id }
    assert record[:facts].any? { |fact| fact[:body] == "Focus follows validated demand." }
  end

  test "record event stores answers against agent questions" do
    @user.update_local_agent_settings("enabled" => "1")
    question = @user.agent_events.create!(
      event_type: "question",
      summary: "What needs attention?",
      payload: { "question" => "What needs attention?" }
    )

    assert_difference "AgentEvent.where(event_type: 'answer').count", 1 do
      result = toolbox.call("record_event", {
        "event_type" => "answer",
        "target_type" => "AgentEvent",
        "target_id" => question.id,
        "summary" => "The active idea needs a clearer next todo.",
        "payload" => {}
      })

      assert_equal true, result.fetch(:ok)
    end

    answer = AgentEvent.where(event_type: "answer").recent.first
    assert_equal question, answer.target
    assert_equal "The active idea needs a clearer next todo.", answer.payload["answer"]
  end

  private

  def toolbox
    LocalAgent::Toolbox.new(user: @user)
  end
end
