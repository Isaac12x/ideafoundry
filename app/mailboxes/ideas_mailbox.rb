class IdeasMailbox < ApplicationMailbox
  before_processing :authenticate_sender

  PARTIAL_MATCH_MIN_LENGTH = 4

  def process
    idea_id = extract_idea_id_from_subject

    if idea_id
      update_existing_idea(idea_id) || create_new_idea
    elsif (matched_idea = find_partial_title_match)
      store_pending_email(matched_idea)
    else
      create_new_idea
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

  def extract_topology_from_body
    body_content = extract_body_content
    match = body_content.match(/#topology:\s*(\w+)/i)
    match ? match[1] : nil
  end

  def find_partial_title_match
    subject = mail.subject.to_s.gsub(/\[IDEA-\d+\]/, '').strip
    return nil if subject.length < PARTIAL_MATCH_MIN_LENGTH

    @user.ideas.find_each do |idea|
      title = idea.title.to_s
      next if title.length < PARTIAL_MATCH_MIN_LENGTH

      if title.downcase.include?(subject.downcase) || subject.downcase.include?(title.downcase)
        return idea
      end
    end

    nil
  end

  def store_pending_email(idea)
    idea.metadata ||= {}
    idea.metadata["pending_emails"] ||= []
    idea.metadata["pending_emails"] << {
      "from" => mail.from.first,
      "subject" => mail.subject,
      "body" => extract_body_content,
      "received_at" => Time.current.iso8601,
      "message_id" => mail.message_id
    }
    idea.save!

    attach_files_to_idea(idea)
  end

  def create_new_idea
    clean_title = mail.subject.to_s.gsub(/\[IDEA-\d+\]/, '').strip

    idea = @user.ideas.create!(
      title: clean_title,
      description: extract_body_content,
      state: :idea_new,
      email_ingested: true
    )

    topology_name = extract_topology_from_body
    if topology_name.present?
      topology = @user.topologies.find_or_create_by!(name: topology_name)
      idea.topologies << topology unless idea.topologies.include?(topology)
    end

    attach_files_to_idea(idea)
    idea.compute_integrity_hash!

    idea
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

  def attach_files_to_idea(idea)
    mail.attachments.each do |attachment|
      next if attachment.inline?

      attachment_body = if attachment.body.respond_to?(:decoded)
                         attachment.body.decoded
                       else
                         attachment.body.to_s
                       end

      idea.attachments.attach(
        io: StringIO.new(attachment_body),
        filename: attachment.filename,
        content_type: attachment.content_type
      )
    end
  end
end
