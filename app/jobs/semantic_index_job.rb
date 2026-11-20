# Keeps the semantic sidecar's KB vectors in step with disk. Delta (default, enqueued by every KB write via
# Kb::TreeBuilder.bust_cache!): stat-walk vs the semantic_index_entries manifest, read + send only new/changed files, delete vanished ones.
# "full" (recurring sweep, catch-all for Finder edits): delta + every DB record. "rebuild": blue/green resend of everything.
# No-op unless SEMANTIC_SERVICE_URL is set.
class SemanticIndexJob < ApplicationJob
  include KbEntrySearch

  queue_as :default
  limits_concurrency to: 1, duration: 45.minutes, key: ->(user_id, *) { user_id } # concurrent busts serialize (blocked, not dropped); outlasts a rebuild drain

  BATCH = 32
  INDEX_ROW = "!index" # reserved manifest row: sig = the sidecar index_id the manifest describes
  DRAIN_TIMEOUT = 30.minutes
  DRAIN_POLL = 5

  def self.sweep
    User.find_each { |u| perform_later(u.id, "full") } if SemanticSearch.enabled?
  end

  def perform(user_id, mode = nil)
    return unless SemanticSearch.enabled?

    @user = User.find_by(id: user_id)
    return unless @user

    health = SemanticSearch.health # nil = sidecar unreachable: the sends below fail and are retried by the next run
    return rebuild if mode == "rebuild" || (health && !health["rebuilding"] && health["index_model"].present? && health["index_model"] != health["model"])

    full = new_index?(health) || mode == "full"
    full_or_delta(full)
  end

  private

  # The manifest only means something against the index it was built for: a wiped volume, new db or committed rebuild has a new id.
  def new_index?(health)
    id = health&.dig("index_id")
    return false if id.blank?

    row = SemanticIndexEntry.find_by(user_id: @user.id, doc_id: INDEX_ROW)
    return false if row&.sig == id

    SemanticIndexEntry.where(user_id: @user.id).delete_all
    store_index_id(id)
    true
  end

  def store_index_id(id)
    now = Time.current
    SemanticIndexEntry.upsert({ user_id: @user.id, doc_id: INDEX_ROW, sig: id, created_at: now, updated_at: now },
                              unique_by: %i[user_id doc_id], update_only: %i[sig updated_at])
  end

  def full_or_delta(full)
    return unless index_kb

    SemanticIndex.sweep_records(@user) if full
  end

  # Blue/green: resend everything into the shadow index, wait for the worker to drain, then flip. Any failure aborts the shadow.
  def rebuild
    return unless SemanticSearch.rebuild!

    SemanticIndexEntry.where(user_id: @user.id).delete_all
    if index_kb && SemanticIndex.sweep_records(@user) && drain_queue && SemanticSearch.rebuild_commit!
      id = SemanticSearch.health&.dig("index_id")
      store_index_id(id) if id.present?
    else
      SemanticSearch.rebuild_abort!
      SemanticIndexEntry.where(user_id: @user.id).delete_all
    end
  end

  def drain_queue
    deadline = Time.current + DRAIN_TIMEOUT
    loop do
      queued = SemanticSearch.health&.dig("queued")
      return false if queued.nil? || Time.current > deadline
      return true if queued.zero?

      sleep DRAIN_POLL
    end
  end

  # true when the sidecar took everything (manifest updated only after each accepted enqueue).
  def index_kb
    known = SemanticIndexEntry.where(user_id: @user.id).where.not(doc_id: INDEX_ROW).pluck(:doc_id, :sig).to_h
    seen = []
    changed = []
    walk_kb_entries.each do |e| # uncached walk: the cached kb_entry_index may predate the write
      id = SemanticSearch.kb_id(@user.id, e[:src], e[:path])
      seen << id
      sig = signature(e)
      changed << [ id, sig, e ] unless known[id] == sig
    end
    changed.each_slice(BATCH) do |batch|
      items = batch.map { |id, _, e| { id: id, sections: sections(e) } }
      return false unless SemanticSearch.enqueue(items)

      now = Time.current
      SemanticIndexEntry.upsert_all(batch.map { |id, sig, _| { user_id: @user.id, doc_id: id, sig: sig, created_at: now, updated_at: now } },
                                    unique_by: %i[user_id doc_id], update_only: %i[sig updated_at])
    end
    gone = known.keys - seen
    @walk_capped.each do |src| # a capped walk never saw the rest of that source: not vanished
      Rails.logger.warn("SemanticIndexJob: KB source #{src} hit the walk cap; skipping deletes for it")
      gone.reject! { |id| id.start_with?(SemanticSearch.kb_id(@user.id, src, "")) }
    end
    gone.each_slice(200) do |ids|
      return false unless SemanticSearch.delete(ids)

      SemanticIndexEntry.where(user_id: @user.id, doc_id: ids).delete_all
    end
    true
  end

  def abs_for(e) = File.join(File.expand_path(KbSource.list(@user)[e[:src]][:path]), e[:path])

  def stat_of(path)
    s = File.stat(path)
    [ s.mtime.to_f, s.size ]
  rescue SystemCallError
    nil
  end

  def signature(e)
    return Digest::MD5.hexdigest(e[:name]) unless e[:type] == "file"

    abs = abs_for(e)
    parts = [ e[:name], stat_of(abs), stat_of(Kb::Note.sidecar(abs)) ]
    parts << ocr_text(e, abs) if Kb::MediaTypes.kind_for(e[:name]) == :image
    Digest::MD5.hexdigest(parts.inspect)
  end

  # Cached OCR only (never triggers a run); never for private/locked paths, whose text must not leave the KB.
  def ocr_text(e, abs)
    base = File.expand_path(KbSource.list(@user)[e[:src]][:path])
    return "" if Kb::Privacy.private?(base, e[:path])

    Kb::ImageOcr.cached(abs)&.dig(:text).to_s
  end

  def sections(e)
    text = kb_file_text(e, DEEP_FILE_BYTES)
    text = ocr_text(e, abs_for(e)) if text.empty? && e[:type] == "file" && Kb::MediaTypes.kind_for(e[:name]) == :image
    [ e[:name], Kb::Note.read(abs_for(e)).to_s.then { |n| e[:type] == "file" ? n : "" }, *text.split(/\n\s*\n/) ].map { |t| t.to_s.dup.force_encoding(Encoding::UTF_8).scrub.strip }.reject(&:empty?) # file reads can come back binary-tagged
  end
end
