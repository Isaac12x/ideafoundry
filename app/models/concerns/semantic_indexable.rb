# Keeps a record's semantic-search vectors current: every commit enqueues SemanticRecordIndexJob (no wait, no debounce; the sidecar
# coalesces bursts and re-embeds only changed sections). Registry for results/sweeps: SemanticIndex.
#
#   semantic_index type: "note", owner: ->(r) { r.idea&.user_id }, sections: ->(r) { [r.body] }, parents: ->(r) { [r.idea] }
#
# sections blank => the doc is deleted (discarded/superseded records). Omit type/sections for a link model that only fans out to `parents`.
module SemanticIndexable
  extend ActiveSupport::Concern

  included { class_attribute :semantic_config, instance_writer: false }

  class_methods do
    def semantic_index(owner:, type: nil, sections: nil, parents: nil)
      self.semantic_config = { type: type, owner: owner, sections: sections, parents: parents }
      after_commit :semantic_reindex_later, if: -> { SemanticSearch.enabled? }
    end
  end

  def semantic_type = semantic_config[:type]
  def semantic_owner_id = semantic_config[:owner].call(self)
  def semantic_sections = Array(semantic_config[:sections]&.call(self)).map { |s| s.to_s.squish }.reject(&:empty?)

  private

  def semantic_reindex_later
    owner = semantic_owner_id
    SemanticRecordIndexJob.perform_later(self.class.name, id, owner) if semantic_type && owner
    Array(semantic_config[:parents]&.call(self)).compact.each do |parent|
      SemanticRecordIndexJob.perform_later(parent.class.name, parent.id, parent.semantic_owner_id) if parent.semantic_owner_id
    end
  end
end
