class CleanOrphanedDraftsJob < ApplicationJob
  queue_as :default

  # Drafts older than this without being promoted are considered abandoned.
  STALE_AFTER = 24.hours

  def perform(stale_after: STALE_AFTER)
    Idea.stale_drafts(stale_after.ago).find_each(&:destroy)
  end
end
