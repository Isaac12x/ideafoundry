module RecordsIdeaHistory
  extend ActiveSupport::Concern

  class_methods do
    def records_idea_history(as:)
      after_create -> { record_idea_history("Added #{as}") }
      after_update -> { record_idea_history("Updated #{as}") }
      after_destroy -> { record_idea_history("Removed #{as}") }
    end
  end

  private

  def record_idea_history(commit_message)
    return if Idea.history_tracking_suppressed?

    target = idea_for_history
    return unless target&.persisted?

    target.record_history!(commit_message, automatic: true)
  end

  def idea_for_history
    return idea if respond_to?(:idea) && association(:idea).loaded?
    return Idea.find_by(id: idea_id) if respond_to?(:idea_id) && idea_id.present?

    nil
  end
end
