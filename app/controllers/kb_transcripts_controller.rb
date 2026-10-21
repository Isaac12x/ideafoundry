# Time-coded transcript for a KB audio/video file: GET reads it (sidecar .vtt, else
# downloaded captions) plus the local transcription state; POST starts local whisper.
# Runs entirely on this machine, so private projects are allowed.
class KbTranscriptsController < ApplicationController
  include KbFileLookup

  before_action :set_user
  before_action :set_file

  def show
    render json: payload
  end

  def create
    return render json: { error: "whisper is not installed." }, status: :unprocessable_content unless Kb::Transcript.available?
    return render json: payload if File.file?(Kb::Transcript.sidecar(@file[:abs]))

    return render json: { error: "This project is locking or unlocking. Try again in a moment." }, status: :conflict if Kb::ProjectLock.busy_path?(@file[:abs])

    if Kb::Transcript.claim!(@file[:abs])
      @download&.update!(transcript_status: "transcribing")
      KbTranscribeJob.perform_later(@file[:abs], @download&.id)
    end
    render json: payload, status: :accepted
  end

  private

  def set_file
    @file = locate_kb_file
    return head(:not_found) unless @file && Kb::Transcript.media?(@file[:abs])

    @download = @user.kb_downloads.for_file(@file[:src], @file[:rel]).first
  end

  # status: ready (cues present; `running` = a local run is also in flight) | running | failed | none
  def payload
    abs = @file[:abs]
    cues = Kb::Transcript.cues(abs, @download)
    sidecar = File.file?(Kb::Transcript.sidecar(abs))
    running = Kb::Transcript.running?(abs)
    status = if cues.any? then "ready" elsif running then "running" elsif Kb::Transcript.error(abs) then "failed" else "none" end
    { status: status, running: running, cues: cues, source: (sidecar ? "sidecar" : "captions" if cues.any?),
      error: Kb::Transcript.error(abs), can_transcribe: Kb::Transcript.available? && !sidecar && !running }
  end
end
