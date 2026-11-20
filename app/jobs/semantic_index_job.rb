# Keeps the semantic sidecar's vectors in step with ideas + KB entries. With an idea_id: that one idea (deleted when
# gone/draft/discarded). Without: full sweep for the user, then prune anything the sidecar holds that no longer exists.
# `sweep` (recurring) enqueues one per user. No-op unless SEMANTIC_SERVICE_URL is set; the service skips unchanged text.
class SemanticIndexJob < ApplicationJob
  include KbEntrySearch

  queue_as :default

  BATCH = 32

  def self.sweep
    User.find_each { |u| perform_later(u.id) } if SemanticSearch.enabled?
  end

  def perform(user_id, idea_id = nil)
    return unless SemanticSearch.enabled?

    @user = User.find_by(id: user_id)
    return unless @user

    idea_id ? index_idea(idea_id) : index_all
  end

  private

  def index_idea(idea_id)
    id = SemanticSearch.idea_id(@user.id, idea_id)
    idea = @user.ideas.non_draft.where(discarded_at: nil).find_by(id: idea_id)
    idea ? SemanticSearch.upsert([ { id: id, text: idea.search_text } ]) : SemanticSearch.delete([ id ])
  end

  def index_all
    keep = []
    docs = Enumerator.new do |y|
      @user.ideas.non_draft.where(discarded_at: nil).includes(:rich_text_description, :notes, :topologies, :themes).find_each do |i|
        y << { id: SemanticSearch.idea_id(@user.id, i.id), text: i.search_text }
      end
      kb_entry_index.each do |e|
        y << { id: SemanticSearch.kb_id(@user.id, e[:src], e[:path]), text: "#{e[:name]} #{e[:note_down]} #{kb_file_text(e, DEEP_FILE_BYTES)}" }
      end
    end
    docs.each_slice(BATCH) do |batch|
      return unless SemanticSearch.upsert(batch) # sidecar down: skip prune too, or a partial keep list would wipe vectors

      keep.concat(batch.map { |d| d[:id] })
    end
    SemanticSearch.prune(SemanticSearch.prefix(@user.id), keep)
  end
end
