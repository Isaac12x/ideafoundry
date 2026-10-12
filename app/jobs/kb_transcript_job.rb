# Fetches the hidden transcript (captions) of a downloaded video into
# kb_downloads.transcript; no captions -> "awaiting_audio" for the future audio service. Transient failures retry with backoff; `sweep`
# (recurring) re-enqueues lost jobs and backfills older downloads.
class KbTranscriptJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5
  STALE_AFTER = 30.minutes # > longest backoff (4**2 min) so retries aren't doubled

  def self.sweep
    likes = ([ "url LIKE '%youtu%'" ] + KbDownload::VIDEO_EXTS.map { |e| "filename LIKE '%#{e}'" }).join(" OR ")
    KbDownload.where(status: "done", transcript_status: nil).where(likes).find_each(&:queue_transcript)
    KbDownload.where(transcript_status: "pending", updated_at: ..STALE_AFTER.ago).find_each do |dl|
      dl.touch
      perform_later(dl.id)
    end
  end

  def perform(download_id)
    dl = KbDownload.find_by(id: download_id)
    return if dl.nil? || dl.transcript_status != "pending"

    video_id, text = Kb::VideoTranscript.fetch(dl.url)
    if text
      dl.update!(transcript: text, video_id: video_id, transcript_status: "done", transcript_error: nil)
    else
      # yt-dlp can exit 0 yet write nothing (YouTube JS-challenge hiccups), so "no subs"
      # is retried like any failure and only becomes "awaiting_audio" after MAX_ATTEMPTS.
      dl.update!(video_id: video_id) if video_id
      retry_or_fail(dl, nil)
    end
  rescue Kb::VideoTranscript::NotInstalled => e
    # ponytail: not counted as an attempt and not re-enqueued; the sweep retries
    # every 15 min, so installing yt-dlp later recovers it. Never "failed".
    dl&.update!(transcript_error: e.message)
  rescue => e
    Rails.logger.error("KbTranscriptJob #{download_id}: #{e.class}: #{e.message}")
    retry_or_fail(dl, e) if dl
  end

  private

  # error nil = no English subtitles found.
  def retry_or_fail(dl, error)
    attempts = dl.transcript_attempts + 1
    message = error ? error.message.truncate(250) : "No English subtitles found."
    if attempts < MAX_ATTEMPTS
      dl.update!(transcript_attempts: attempts, transcript_error: message)
      self.class.set(wait: (attempts**2).minutes).perform_later(dl.id)
    else
      dl.update!(transcript_attempts: attempts, transcript_status: error ? "failed" : "awaiting_audio", transcript_error: message)
    end
  end
end
