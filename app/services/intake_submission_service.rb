class IntakeSubmissionService
  Result = Struct.new(:submission, :idea, :action, keyword_init: true) do
    def created?
      action == :created
    end

    def target_type
      idea.present? ? "idea" : "submission"
    end
  end

  def initialize(user:, title: nil, body: nil, source: nil, source_reference: nil, priority: nil, raw_payload: nil, attachments: [], temporary_idea_id: nil)
    @user = user
    @title = title
    @body = body
    @source = source
    @source_reference = source_reference
    @priority = priority
    @raw_payload = raw_payload
    @attachments = attachments
    @temporary_idea_id = temporary_idea_id
  end

  def call
    temporary_idea_id.present? ? append_to_existing! : create_submission!
  end

  private

  attr_reader :attachments, :body, :priority, :raw_payload, :source, :source_reference, :temporary_idea_id, :title, :user

  def create_submission!
    submission = user.submissions.build(title: resolved_title)
    submission.append_intake_update!(
      title: title,
      body: body,
      source: resolved_source,
      source_reference: source_reference,
      priority: resolved_priority,
      raw_payload: raw_payload
    )
    attach_to_submission(submission)

    Result.new(submission:, action: :created)
  end

  def append_to_existing!
    submission = user.submissions.find_by_reference!(temporary_idea_id)

    if submission.approved? && submission.idea.present?
      submission.record_intake_event!(
        title: title,
        body: body,
        source: resolved_source,
        source_reference: source_reference,
        raw_payload: raw_payload,
        target: "idea"
      )
      submission.idea.append_intake_update!(
        body: body,
        source: resolved_source,
        intake_reference: submission.temporary_idea_id
      )
      attach_to_idea(submission.idea)

      Result.new(submission:, idea: submission.idea, action: :updated)
    else
      submission.append_intake_update!(
        title: title,
        body: body,
        source: resolved_source,
        source_reference: source_reference,
        priority: resolved_priority,
        raw_payload: raw_payload
      )
      attach_to_submission(submission)

      Result.new(submission:, idea: submission.idea, action: :updated)
    end
  end

  def attach_to_submission(submission)
    return if attachments.empty?

    attachments.each do |attachment|
      submission.files.attach(
        io: attachment[:io],
        filename: attachment[:filename],
        content_type: attachment[:content_type]
      )
    end
  end

  def attach_to_idea(idea)
    return if attachments.empty?

    attachments.each do |attachment|
      idea.attachments.attach(
        io: attachment[:io],
        filename: attachment[:filename],
        content_type: attachment[:content_type]
      )
    end

    idea.create_version("Updated via intake #{temporary_idea_id}") if attachments.any? && body.to_s.strip.blank?
  end

  def resolved_priority
    Submission.priorities.key?(priority.to_s) ? priority.to_s : "normal"
  end

  def resolved_source
    source.presence || "api"
  end

  def resolved_title
    title.presence || "Untitled intake idea"
  end
end
