class CleanOrphanedDraftsJob < ApplicationJob
  queue_as :default

  # The stale age applies only to empty drafts. Meaningful drafts are user data
  # and remain available until the user promotes or discards them.
  STALE_AFTER = 24.hours

  def perform(stale_after: STALE_AFTER)
    Idea.drafts.where("ideas.created_at = ideas.updated_at").where("ideas.created_at < ?", stale_after.ago).find_each do |candidate|
      Idea.transaction do
        idea = Idea.lock.find_by(id: candidate.id)
        idea&.destroy if idea&.draft? && idea.blank_draft? && idea.created_at < stale_after.ago && idea.updated_at == idea.created_at
      end
    end
  end
end
