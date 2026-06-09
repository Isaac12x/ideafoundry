class IdeasMailbox < ApplicationMailbox
  before_processing :authenticate_sender

  INTAKE_REFERENCE_PATTERN = /\bIDEA-TMP-\d{8}-[A-Z0-9]{4}\b/i

  def process
    idea_id = extract_idea_id_from_subject

    if idea_id
      update_existing_idea(idea_id) || create_or_update_submission
    else
      create_or_update_submission
    end
  end

  private

  def authenticate_sender
    user = User.find_by(email: mail.from.first)

    unless user
      bounced!
    end

    @user = user
  end

  def extract_idea_id_from_subject
    match = mail.subject&.match(/\[IDEA-(\d+)\]/)
    match ? match[1].to_i : nil
  end

  def extract_intake_reference
    searchable_content = [mail.subject, extract_body_content].join("\n")
    match = searchable_content.match(INTAKE_REFERENCE_PATTERN)
    match ? match[0].upcase : nil
  end

  def extract_topology_from_body
    body_content = extract_body_content
    match = body_content.match(/#topology:\s*([^\r\n]+)/i)
    match ? match[1].strip : nil
  end

  def extract_priority_from_body
    body_content = extract_body_content
    match = body_content.match(/#priority:\s*(low|normal|high)\b/i)
    match ? match[1].downcase : nil
  end

  def create_or_update_submission
    temporary_idea_id = extract_intake_reference

    IntakeSubmissionService.new(
      user: @user,
      title: temporary_idea_id.present? ? nil : clean_subject,
      body: extract_body_content,
      source: "email",
      source_reference: email_source_reference,
      priority: extract_priority_from_body,
      raw_payload: email_raw_payload(temporary_idea_id),
      attachments: normalized_attachments,
      temporary_idea_id: temporary_idea_id
    ).call
  end

  def update_existing_idea(idea_id)
    idea = @user.ideas.find_by(id: idea_id)
    return nil unless idea

    current_description = idea.description.to_plain_text
    new_content = extract_body_content

    idea.description = "#{current_description}\n\n---\n\n#{new_content}"
    idea.save!

    attach_files_to_idea(idea)
    idea.compute_integrity_hash!

    idea
  end

  def extract_body_content
    if mail.html_part
      mail.html_part.decoded
    elsif mail.text_part
      mail.text_part.decoded
    else
      mail.decoded
    end
  end

  def clean_subject
    mail.subject.to_s
        .gsub(/\[IDEA-\d+\]/i, "")
        .gsub(INTAKE_REFERENCE_PATTERN, "")
        .gsub(/\A\s*(re|fw|fwd):\s*/i, "")
        .strip
        .presence
  end

  def email_source_reference
    mail.message_id.presence || "action_mailbox:#{inbound_email.id}"
  end

  def email_raw_payload(temporary_idea_id)
    {
      "from" => mail.from&.first,
      "to" => Array(mail.to),
      "cc" => Array(mail.cc),
      "subject" => mail.subject.to_s,
      "message_id" => mail.message_id,
      "date" => mail.date&.iso8601,
      "content_type" => mail.mime_type || mail.content_type,
      "topology" => extract_topology_from_body,
      "priority" => extract_priority_from_body,
      "intake_reference" => temporary_idea_id,
      "attachments" => attachment_metadata
    }.compact
  end

  def attachment_metadata
    mail.attachments.reject(&:inline?).map do |attachment|
      {
        "filename" => attachment.filename,
        "content_type" => attachment.content_type,
        "bytes" => decoded_attachment_body(attachment).bytesize
      }
    end
  end

  def normalized_attachments
    mail.attachments.filter_map do |attachment|
      next if attachment.inline?

      {
        io: StringIO.new(decoded_attachment_body(attachment)),
        filename: attachment.filename,
        content_type: attachment.content_type
      }
    end
  end

  def attach_files_to_idea(idea)
    mail.attachments.each do |attachment|
      next if attachment.inline?

      idea.attachments.attach(
        io: StringIO.new(decoded_attachment_body(attachment)),
        filename: attachment.filename,
        content_type: attachment.content_type
      )
    end
  end

  def decoded_attachment_body(attachment)
    if attachment.body.respond_to?(:decoded)
      attachment.body.decoded
    else
      attachment.body.to_s
    end
  end
end
