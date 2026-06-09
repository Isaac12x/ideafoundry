require "test_helper"

class IdeasMailboxTest < ActionMailbox::TestCase
  setup do
    @user = users(:one)
  end

  test "creates pending submission from email" do
    assert_no_difference "Idea.count" do
      assert_difference "Submission.count", 1 do
        receive_inbound_email_from_mail(
          from: @user.email,
          to: "ideas@example.com",
          subject: "My Awesome Idea",
          body: "This is a great idea for a new product."
        )
      end
    end

    submission = Submission.last
    assert_equal "My Awesome Idea", submission.title
    assert_includes submission.body, "This is a great idea for a new product."
    assert_equal @user, submission.user
    assert_predicate submission, :pending?
    assert_equal "email", submission.source
    assert_match(/\AIDEA-TMP-\d{8}-[A-Z0-9]{4}\z/, submission.temporary_idea_id)
    assert_equal @user.email, submission.raw_data.dig("last_payload", "from")
    assert_equal "My Awesome Idea", submission.raw_data.dig("last_payload", "subject")
  end

  test "captures topology directive in email submission raw data" do
    receive_inbound_email_from_mail(
      from: @user.email,
      to: "ideas@example.com",
      subject: "Product Idea",
      body: "This is my idea.\n\n#topology: technology"
    )

    submission = Submission.last
    assert_equal "Product Idea", submission.title
    assert_equal "technology", submission.raw_data.dig("last_payload", "topology")
  end

  test "appends email to existing submission when temporary idea id is in subject" do
    submission = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway"
    ).call.submission

    assert_no_difference "Submission.count" do
      receive_inbound_email_from_mail(
        from: @user.email,
        to: "ideas@example.com",
        subject: "Re: #{submission.temporary_idea_id}",
        body: "Follow-up context from email."
      )
    end

    submission.reload
    assert_includes submission.body, "Initial gateway context"
    assert_includes submission.body, "Follow-up context from email."
    assert_equal 2, submission.raw_data["events"].size
  end

  test "appends email to approved submission target when temporary idea id is in body" do
    submission = IntakeSubmissionService.new(
      user: @user,
      title: "War room concept",
      body: "Initial gateway context",
      source: "openclaw_gateway"
    ).call.submission
    idea = SubmissionApprover.new(submission).approve!

    receive_inbound_email_from_mail(
      from: @user.email,
      to: "ideas@example.com",
      subject: "More detail",
      body: "Temporary reference: #{submission.temporary_idea_id}\n\nPost-approval email detail."
    )

    idea.reload
    submission.reload
    assert_includes idea.description.to_plain_text, "Post-approval email detail."
    assert_equal 2, submission.raw_data["events"].size
  end

  test "attaches files from email to submission" do
    inbound_email = create_inbound_email_from_fixture("welcome.eml")

    assert_no_difference "Idea.count" do
      assert_difference "Submission.count", 1 do
        assert_difference "ActiveStorage::Attachment.count", 1 do
          inbound_email.route
        end
      end
    end

    submission = Submission.last
    assert_equal "Test Idea with Attachment", submission.title
    assert_equal 1, submission.files.count
    assert_equal "test.pdf", submission.files.first.filename.to_s
  end

  test "directly updates existing idea when IDEA-ID is in subject" do
    existing_idea = ideas(:one)
    original_description = existing_idea.description.to_plain_text

    assert_no_difference "Submission.count" do
      assert_no_difference "Idea.count" do
        receive_inbound_email_from_mail(
          from: @user.email,
          to: "ideas@example.com",
          subject: "[IDEA-#{existing_idea.id}] Additional thoughts",
          body: "Here are some more details about this idea."
        )
      end
    end

    existing_idea.reload
    updated_description = existing_idea.description.to_plain_text
    assert_includes updated_description, original_description
    assert_includes updated_description, "Here are some more details about this idea."
    assert_includes updated_description, "---"
  end

  test "creates submission when explicit idea id does not exist" do
    assert_no_difference "Idea.count" do
      assert_difference "Submission.count", 1 do
        receive_inbound_email_from_mail(
          from: @user.email,
          to: "ideas@example.com",
          subject: "[IDEA-99999] Update non-existent idea",
          body: "This should create an intake submission."
        )
      end
    end

    submission = Submission.last
    assert_equal "Update non-existent idea", submission.title
    assert_includes submission.body, "This should create an intake submission."
  end

  test "handles HTML email body in submission" do
    receive_inbound_email_from_mail(
      from: @user.email,
      to: "ideas@example.com",
      subject: "HTML Email",
      body: "<p>This is <strong>HTML</strong> content.</p>",
      content_type: "text/html"
    )

    submission = Submission.last
    assert_includes submission.body, "HTML"
  end

  test "bounces email from unauthorized sender" do
    assert_no_difference "Submission.count" do
      assert_no_difference "Idea.count" do
        inbound_email = receive_inbound_email_from_mail(
          from: "unauthorized@example.com",
          to: "ideas@example.com",
          subject: "Unauthorized Idea",
          body: "This should be bounced."
        )

        assert inbound_email.bounced?
      end
    end
  end
end
