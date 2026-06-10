module IdeaHistoryActionTextRichText
  extend ActiveSupport::Concern

  included do
    after_save :record_idea_text_history
    after_destroy :record_idea_text_history
  end

  private

  def record_idea_text_history
    return if Idea.history_tracking_suppressed?
    return unless record.is_a?(Idea)

    record.record_history!("Updated description", automatic: true)
  end
end

Rails.application.config.to_prepare do
  unless ActionText::RichText < IdeaHistoryActionTextRichText
    ActionText::RichText.include(IdeaHistoryActionTextRichText)
  end
end
