class EventNotificationJob < ApplicationJob
  queue_as :default

  def perform(idea_id:, user_id:, event_type:, metadata: {})
    user = User.find_by(id: user_id)
    idea = Idea.find_by(id: idea_id)
    return unless user && idea

    recipients = user.email_recipients
    return if recipients.empty?

    template = user.notification_template_for(event_type)

    recipients.each do |recipient|
      IdeaMailer.public_send(
        template, idea, recipient,
        event_type: event_type,
        metadata: metadata.deep_stringify_keys
      ).deliver_later
    end
  end
end
