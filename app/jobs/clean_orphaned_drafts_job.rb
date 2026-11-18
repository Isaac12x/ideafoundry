class CleanOrphanedDraftsJob < ApplicationJob
  queue_as :default

  # Drafts older than this without being promoted are considered abandoned.
  STALE_AFTER = 24.hours

  # Empty drafts (opened the form, typed nothing) are never worth queueing.
  BLANK_AFTER = 1.hour

  def perform(stale_after: STALE_AFTER)
    Idea.blank_drafts.select { |idea| idea.updated_at < BLANK_AFTER.ago }.each(&:destroy)
    Idea.stale_drafts(stale_after.ago).find_each(&:destroy)
  end
end
