# Sends one DB record's sections to the semantic sidecar (empty sections = delete). Enqueued by SemanticIndexable on every commit.
# Missing/discarded/superseded records come out with no sections and are deleted. No-op unless SEMANTIC_SERVICE_URL is set.
class SemanticRecordIndexJob < ApplicationJob
  queue_as :default

  # owner_id is passed in because a destroyed record can no longer tell us whose doc to delete.
  def perform(class_name, id, owner_id)
    return unless SemanticSearch.enabled?

    klass = class_name.safe_constantize
    return unless klass && klass < SemanticIndexable

    record = klass.find_by(id: id)
    type = record ? record.semantic_type : SemanticIndex.type_for(klass)
    return unless type

    SemanticSearch.enqueue([ { id: SemanticSearch.record_id(owner_id, type, id), sections: record ? record.semantic_sections : [] } ])
  end
end
