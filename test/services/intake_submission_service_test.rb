require "test_helper"

class IntakeSubmissionServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "creates a pending submission with a human-readable temporary idea id" do
    result = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway",
      raw_payload: { "channel" => "war-room" }
    ).call

    submission = result.submission

    assert result.created?
    assert_predicate submission, :pending?
    assert_match(/\AIDEA-TMP-\d{8}-[A-Z0-9]{4}\z/, submission.temporary_idea_id)
    assert_equal "submission", result.target_type
    assert_equal "War room concept", submission.title
    assert_includes submission.body, "Initial gateway context"
    assert_equal "openclaw_gateway", submission.source
    assert_equal 1, submission.raw_data["events"].size
  end

  test "appends follow-up context to an existing pending submission" do
    submission = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway"
    ).call.submission

    assert_no_difference "Submission.count" do
      IntakeSubmissionService.new(
        user: @user,
        temporary_idea_id: submission.temporary_idea_id,
        body: "Second chat message",
        source: "openclaw_gateway"
      ).call
    end

    submission.reload

    assert_includes submission.body, "Initial gateway context"
    assert_includes submission.body, "Second chat message"
    assert_equal 2, submission.raw_data["events"].size
    assert_predicate submission, :pending?
  end

  test "keeps the temporary idea id usable after approval" do
    submission = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway"
    ).call.submission

    idea = SubmissionApprover.new(submission).approve!

    result = IntakeSubmissionService.new(
      user: @user,
      temporary_idea_id: submission.temporary_idea_id,
      body: "Post-approval gateway detail",
      source: "openclaw_gateway"
    ).call

    submission.reload
    idea.reload

    assert_equal idea, result.idea
    assert_equal "idea", result.target_type
    assert_includes idea.description.to_plain_text, "Post-approval gateway detail"
    assert_equal 2, submission.raw_data["events"].size
  end

  test "reopens rejected submissions when new gateway context arrives" do
    submission = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway"
    ).call.submission
    submission.reject!("Need more detail")

    IntakeSubmissionService.new(
      user: @user,
      temporary_idea_id: submission.temporary_idea_id,
      body: "More detail from the chat",
      source: "openclaw_gateway"
    ).call

    submission.reload

    assert_predicate submission, :pending?
    assert_nil submission.review_notes
    assert_nil submission.reviewed_at
    assert_includes submission.body, "More detail from the chat"
  end
end
