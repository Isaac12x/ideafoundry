# Hidden, agent-only knowledge distilled from KB media. Never shown in the UI.
#
# IMPLEMENTATION NOTE: this is the FIRST iteration. Facts come only from the
# YouTube auto/manual captions transcript (pipeline "transcript_v1"). The final
# iteration should run a separate service over the video's AUDIO (proper
# speech-to-text) and another over its IMAGES/frames (vision), then combine
# both into a better digest (pipeline "av_v1") that supersedes transcript_v1
# rows via `MediaDigest.record!`. The audio service should pick up kb_downloads
# with transcript_status "awaiting_audio" (no captions / non-English / direct
# video files) and also re-process "done" ones for the better av_v1 digest.
# Local whisper (Kb::Transcript) now covers the transcript part: it writes a sidecar
# .vtt beside the media. Video files placed in the KB directly (not via a KbDownload)
# have no row yet: digests for them still need one (media_digests.kb_download_id is NOT NULL).
class MediaDigest < ApplicationRecord
  belongs_to :user
  belongs_to :kb_download
  belongs_to :superseded_by, class_name: "MediaDigest", optional: true

  # Lowest to highest quality. A lower-ranked write never replaces a higher one.
  PIPELINES = %w[transcript_v1 av_v1].freeze
  SEARCH_LIMIT = 10

  validates :pipeline, inclusion: { in: PIPELINES }
  validates :body, presence: true

  scope :current, -> { where(superseded_at: nil) }

  # Newest write wins, unless a current digest from a better pipeline exists
  # (then the new row is stored already superseded by it, so history is kept).
  def self.record!(user:, kb_download:, body:, pipeline: PIPELINES.first)
    transaction do
      digest = create!(user: user, kb_download: kb_download, body: body, pipeline: pipeline)
      older = current.where(kb_download_id: kb_download.id).where.not(id: digest.id)
      best = older.max_by { |d| PIPELINES.index(d.pipeline) }
      if best && PIPELINES.index(best.pipeline) > PIPELINES.index(pipeline)
        digest.update!(superseded_at: Time.current, superseded_by_id: best.id)
      else
        older.update_all(superseded_at: Time.current, superseded_by_id: digest.id)
      end
      digest
    end
  end

  # ponytail: keyword LIKE search ranked by count of matching terms. No
  # embeddings in the app yet; the agent (an LLM) does the semantic part by
  # issuing several queries. Upgrade: sqlite-vec / embeddings column once a
  # local embedding endpoint exists.
  def self.search(query, limit: SEARCH_LIMIT)
    terms = query.to_s.downcase.scan(/[[:alnum:]_'-]+/).select { |t| t.length >= 3 }.uniq
    return none if terms.empty?

    hits = terms.map do |t|
      like = "%#{sanitize_sql_like(t)}%"
      sanitize_sql_array([ "(lower(media_digests.body) LIKE ? ESCAPE '\\' OR lower(COALESCE(kb_downloads.title, '')) LIKE ? ESCAPE '\\')", like, like ])
    end
    score = hits.map { |h| "CASE WHEN #{h} THEN 1 ELSE 0 END" }.join(" + ")
    current.joins(:kb_download).where(hits.join(" OR "))
           .order(Arel.sql("(#{score}) DESC"), created_at: :desc).limit(limit)
  end
end
