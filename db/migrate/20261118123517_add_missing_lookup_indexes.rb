# Audit: foreign keys and hot filters that had no index (full scans on join/lookup).
class AddMissingLookupIndexes < ActiveRecord::Migration[8.1]
  INDEXES = {
    ideas: [ [ :user_id, :discarded_at, :updated_at ] ], # search/list: per-user, not archived, newest first
    facts: [ :user_id ],
    templates: [ :topology_id ],
    media_digests: [ :superseded_by_id ],
    knowledge_extractions: [ :output_attachment_id ],
    kb_downloads: [ :video_id ]
  }.freeze

  def change
    INDEXES.each do |table, defs|
      defs.each { |cols| add_index table, cols, if_not_exists: true }
    end
  end
end
