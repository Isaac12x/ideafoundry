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

  # OCR text of idea attachments is searchable semantically (only Idea-owned ones with text; anything else maps to no sections = delete).
  unless ActiveStorage::Attachment < SemanticIndexable
    ActiveStorage::Attachment.include(SemanticIndexable)
    ActiveStorage::Attachment.semantic_index type: "attachment", owner: ->(r) { r.record.try(:user_id) },
                                             sections: ->(r) { r.record_type == "Idea" && r.ocr_text.present? ? [ r.filename.to_s, *SemanticIndex.split(r.ocr_text) ] : [] }
  end
end
