module IdeaHistoryActiveStorageAttachment
  extend ActiveSupport::Concern

  included do
    after_create :record_idea_media_history
    after_destroy :record_idea_media_history
  end

  private

  def record_idea_media_history
    return if Idea.history_tracking_suppressed?

    target = idea_for_media_history
    return unless target&.persisted?

    target.record_history!("Updated media", automatic: true)
  end

  def idea_for_media_history
    case record
    when Idea
      record
    when Drawing
      record.idea
    end
  end
end

Rails.application.config.to_prepare do
  unless ActiveStorage::Attachment < IdeaHistoryActiveStorageAttachment
    ActiveStorage::Attachment.include(IdeaHistoryActiveStorageAttachment)
  end
end
