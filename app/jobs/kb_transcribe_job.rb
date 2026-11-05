# Local whisper transcription of one KB audio/video file into its sidecar .vtt
# (see Kb::Transcript). The controller/sweep claimed the lock. When the file came
# from a download, its transcript columns follow so search/digests see the text.
class KbTranscribeJob < ApplicationJob
  queue_as :transcribe # own low-priority worker (config/queue.yml): whisper can't starve other jobs

  def perform(abs, download_id = nil)
    download = KbDownload.find_by(id: download_id)
    return release(abs, download) if Kb::ProjectLock.busy_path?(abs)

    path = Kb::Transcript.transcribe!(abs)
    # Locking started meanwhile: the sidecar stays, the sweep adopts it after unlock.
    return release(abs, download) if Kb::ProjectLock.busy_path?(abs) || !File.exist?(path)

    text = Kb::VideoTranscript.render(File.read(path), "vtt")
    download&.update!(transcript: text, transcript_status: "done", transcript_error: nil) if text
    download&.update!(transcript_status: "awaiting_audio", transcript_error: "Transcript came back empty.") unless text
  rescue Kb::Transcript::Error, SystemCallError => e
    Rails.logger.warn("KbTranscribeJob #{abs}: #{e.message}")
    FileUtils.mkdir_p(Kb::Transcript.state_dir)
    File.write(Kb::Transcript.state_file(abs, "err"), e.message.truncate(300))
    # attempts > MAX_ATTEMPTS = whisper gave up: KbTranscriptJob.sweep won't auto-revive it (the Transcribe button still works).
    download&.update!(transcript_status: "failed", transcript_error: e.message.truncate(250), transcript_attempts: KbTranscriptJob::MAX_ATTEMPTS + 1)
  end

  private

  # Project is locking: write nothing, free the claim, let the sweep retry.
  def release(abs, download)
    FileUtils.rm_f(Kb::Transcript.state_file(abs, "lock"))
    download&.update_columns(transcript_status: "awaiting_audio")
  end
end
