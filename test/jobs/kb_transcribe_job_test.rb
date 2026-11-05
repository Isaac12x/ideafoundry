require "test_helper"

class KbTranscribeJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @dir = Rails.root.join("tmp", "kb-transcribe-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@dir)
    @media = File.join(@dir, "talk.mp4")
    File.binwrite(@media, "x")
    @download = @user.kb_downloads.create!(source_index: 0, source_path: @dir, dir: "", url: "https://example.com/talk.mp4",
                                           status: "done", filename: "talk.mp4", transcript_status: "transcribing")
  end

  teardown do
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(Kb::Transcript.state_dir)
  end

  test "writes nothing while the project is locking" do
    Kb::ProjectLock::STATE[File.expand_path(@dir)] = { op: :lock }
    Kb::Transcript.stub(:transcribe!, ->(_abs) { flunk "must not transcribe" }) { KbTranscribeJob.perform_now(@media, @download.id) }
    assert_nil @download.reload.transcript
    assert_equal "awaiting_audio", @download.transcript_status
  ensure
    Kb::ProjectLock::STATE.clear
  end

  test "stores the sidecar text on the download" do
    fake = lambda do |abs|
      File.write(Kb::Transcript.sidecar(abs), "WEBVTT\n\n00:00.000 --> 00:02.000\nhi there\n")
      Kb::Transcript.sidecar(abs)
    end
    Kb::Transcript.stub(:transcribe!, fake) { KbTranscribeJob.perform_now(@media, @download.id) }

    @download.reload
    assert_equal "done", @download.transcript_status
    assert_equal "00:00 - hi there\n", @download.transcript
  end

  test "a whisper failure is recorded for the UI and the download" do
    boom = ->(_abs) { raise Kb::Transcript::Error, "whisper failed." }
    Kb::Transcript.stub(:transcribe!, boom) { KbTranscribeJob.perform_now(@media, @download.id) }

    assert_equal "failed", @download.reload.transcript_status
    assert_equal "whisper failed.", Kb::Transcript.error(@media)
  end

  test "sweep hands awaiting_audio downloads to whisper, adopts existing sidecars, and skips missing files" do
    @download.update!(transcript_status: "awaiting_audio")
    Kb::Transcript.stub(:available?, true) do
      assert_enqueued_with(job: KbTranscribeJob, args: [ @media, @download.id ]) { KbTranscriptJob.transcribe_waiting }
    end
    assert_equal "transcribing", @download.reload.transcript_status

    @download.update!(transcript_status: "awaiting_audio")
    FileUtils.rm_rf(Kb::Transcript.state_dir)
    File.write(Kb::Transcript.sidecar(@media), "WEBVTT\n\n00:00.000 --> 00:02.000\nalready here\n")
    assert_no_enqueued_jobs { KbTranscriptJob.transcribe_waiting }
    assert_equal [ "done", "00:00 - already here\n" ], [ @download.reload.transcript_status, @download.transcript ]

    @download.update!(transcript_status: "awaiting_audio", filename: "gone.mp4")
    assert_no_enqueued_jobs { KbTranscriptJob.transcribe_waiting }
  end

  test "whisper timeout marks failed, gives up on auto-revival" do
    slow = ->(_abs) { raise Kb::Transcript::Error, "Transcription timed out (whisper timed out after 90s)." }
    Kb::Transcript.stub(:transcribe!, slow) { KbTranscribeJob.perform_now(@media, @download.id) }
    @download.reload.update_columns(updated_at: 2.days.ago)

    assert_equal "failed", @download.transcript_status
    assert_operator @download.transcript_attempts, :>, KbTranscriptJob::MAX_ATTEMPTS
    assert_no_enqueued_jobs(only: KbTranscriptJob) { KbTranscriptJob.sweep }
    assert_equal "failed", @download.reload.transcript_status
  end

  test "transcribe runs on its own queue" do
    assert_equal "transcribe", KbTranscribeJob.new.queue_name
  end
end
