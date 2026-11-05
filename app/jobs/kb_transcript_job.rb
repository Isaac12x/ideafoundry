# Fetches the hidden transcript (captions) of a downloaded video into
# kb_downloads.transcript; no captions -> "awaiting_audio", which the sweep hands to
# local whisper (KbTranscribeJob -> "transcribing" -> "done"). Transient failures retry with backoff; `sweep`
# (recurring) re-enqueues lost jobs and backfills older downloads.
class KbTranscriptJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5
  STALE_AFTER = 30.minutes # > longest backoff (4**2 min) so retries aren't doubled
  REVIVE_FAILED_AFTER = 1.day # YouTube/yt-dlp breakage is usually fixed by then
  AUDIO_PER_SWEEP = 2 # whisper is CPU-heavy; a few files per 15-minute sweep

  def self.sweep
    likes = ([ "url LIKE '%youtu%'" ] + KbDownload::VIDEO_EXTS.map { |e| "filename LIKE '%#{e}'" }).join(" OR ")
    KbDownload.where(status: "done", transcript_status: nil).where(likes).find_each(&:queue_transcript)
    KbDownload.where(transcript_status: "pending", updated_at: ..STALE_AFTER.ago).find_each do |dl|
      dl.touch
      perform_later(dl.id)
    end
    transcribe_waiting if Kb::Transcript.available?
    # Only YouTube rows end "failed" (see retry_or_fail); give them a fresh run.
    KbDownload.where(transcript_status: "failed", transcript_attempts: ..MAX_ATTEMPTS, updated_at: ..REVIVE_FAILED_AFTER.ago).find_each do |dl|
      dl.update!(transcript_status: "pending", transcript_attempts: 0)
      perform_later(dl.id)
    end
  end

  # awaiting_audio rows -> local whisper, a couple per run. A leftover sidecar .vtt is adopted instead.
  def self.transcribe_waiting
    KbDownload.where(transcript_status: "transcribing", updated_at: ..(Kb::Transcript::LOCK_TTL + 1.hour).ago)
              .update_all(transcript_status: "awaiting_audio")
    started = 0
    KbDownload.where(transcript_status: "awaiting_audio").find_each do |dl|
      break if started >= AUDIO_PER_SWEEP

      abs = dl.file_abs
      next unless abs && Kb::Transcript.media?(abs) && !dl.project_blocked?

      if File.file?(Kb::Transcript.sidecar(abs))
        text = Kb::VideoTranscript.render(File.read(Kb::Transcript.sidecar(abs)), "vtt")
        dl.update!(transcript: text, transcript_status: "done", transcript_error: nil) if text
      elsif Kb::Transcript.claim!(abs)
        dl.update!(transcript_status: "transcribing")
        KbTranscribeJob.perform_later(abs, dl.id)
        started += 1
      end
    end
  end

  def perform(download_id)
    dl = KbDownload.find_by(id: download_id)
    return if dl.nil? || dl.transcript_status != "pending"
    return if dl.project_blocked? # stays pending: the sweep re-enqueues it once unlocked

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

  # error nil = no English subtitles found. Out of attempts: anything without
  # captions waits for the audio service; only YouTube errors end "failed" (the
  # captions exist there, so the sweep retries them daily).
  def retry_or_fail(dl, error)
    attempts = dl.transcript_attempts + 1
    message = error ? error.message.truncate(250) : "No English subtitles found."
    if attempts < MAX_ATTEMPTS
      dl.update!(transcript_attempts: attempts, transcript_error: message)
      self.class.set(wait: (attempts**2).minutes).perform_later(dl.id)
    else
      dl.update!(transcript_attempts: attempts, transcript_status: error && dl.youtube? ? "failed" : "awaiting_audio", transcript_error: message)
    end
  end
end
