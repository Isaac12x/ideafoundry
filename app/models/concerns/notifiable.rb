module Notifiable
  extend ActiveSupport::Concern

  included do
    after_save :check_notification_triggers
  end

  private

  def check_notification_triggers
    return unless user

    events = []

    if saved_change_to_attribute?(:id) # newly created
      events << "created"
    end

    if saved_change_to_attribute?(:state)
      events << "state_changed"
    end

    if saved_change_to_attribute?(:computed_score)
      old_score, new_score = saved_change_to_attribute(:computed_score)
      if old_score && new_score && (new_score - old_score).abs >= 0.5
        events << "score_changed"
      end
    end

    events.each do |event|
      next unless user.notification_enabled?(event)

      EventNotificationJob.perform_later(
        idea_id: id,
        user_id: user_id,
        event_type: event,
        metadata: notification_metadata(event)
      )
    end
  end

  def notification_metadata(event)
    meta = { idea_title: title, state: state }

    case event
    when "state_changed"
      old_state, new_state = saved_change_to_attribute(:state)
      meta[:old_state] = old_state
      meta[:new_state] = new_state
    when "score_changed"
      old_score, new_score = saved_change_to_attribute(:computed_score)
      meta[:old_score] = old_score
      meta[:new_score] = new_score
    end

    meta
  end
end
