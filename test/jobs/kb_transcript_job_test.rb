require "test_helper"

class KbTranscriptJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  def video(**attrs)
    @user.kb_downloads.create!({ source_index: 0, dir: "", url: "https://www.youtube.com/watch?v=abc",
                                 format: "auto", status: "done", filename: "v.mp4", transcript_status: "pending" }.merge(attrs))
  end

  def run_with(result, dl)
    Kb::VideoTranscript.stub(:fetch, result) { KbTranscriptJob.perform_now(dl.id) }
    dl.reload
  end

  test "stores the transcript" do
    dl = run_with(->(_) { [ "abc", "00:00 - hi\n" ] }, video)
    assert_equal [ "done", "abc", "00:00 - hi\n" ], [ dl.transcript_status, dl.video_id, dl.transcript ]
  end

  test "no subtitles retries, then becomes awaiting_audio" do
    dl = nil
    assert_enqueued_with(job: KbTranscriptJob) { dl = run_with(->(_) { [ "abc", nil ] }, video) }
    assert_equal [ "pending", 1, "abc" ], [ dl.transcript_status, dl.transcript_attempts, dl.video_id ]

    dl = run_with(->(_) { [ "abc", nil ] }, video(transcript_attempts: KbTranscriptJob::MAX_ATTEMPTS - 1))
    assert_equal [ "awaiting_audio", "No English subtitles found." ], [ dl.transcript_status, dl.transcript_error ]
  end

  test "failure retries with backoff and stays pending" do
    dl = video
    assert_enqueued_with(job: KbTranscriptJob) do
      dl = run_with(->(_) { raise Kb::VideoTranscript::Error, "boom" }, dl)
    end
    assert_equal [ "pending", 1, "boom" ], [ dl.transcript_status, dl.transcript_attempts, dl.transcript_error ]
  end

  test "gives up after max attempts" do
    dl = run_with(->(_) { raise "boom" }, video(transcript_attempts: KbTranscriptJob::MAX_ATTEMPTS - 1))
    assert_equal "failed", dl.transcript_status
    assert_no_enqueued_jobs
  end

  test "missing yt-dlp stays pending without burning attempts" do
    dl = run_with(->(_) { raise Kb::VideoTranscript::NotInstalled, "yt-dlp is not installed." }, video)
    assert_equal [ "pending", 0 ], [ dl.transcript_status, dl.transcript_attempts ]
    assert_no_enqueued_jobs
  end

  test "ignores non-pending downloads" do
    dl = video(transcript_status: "done")
    Kb::VideoTranscript.stub(:fetch, ->(_) { flunk "fetched" }) { KbTranscriptJob.perform_now(dl.id) }
    assert_equal "done", dl.reload.transcript_status
  end

  test "sweep re-enqueues stale pending and backfills old youtube downloads" do
    stale = video
    stale.update_columns(updated_at: 1.hour.ago)
    fresh = video
    old = video(transcript_status: nil)
    site = video(transcript_status: nil, url: "https://vimeo.com/1", filename: "clip.mp4")
    direct = video(transcript_status: nil, url: "https://example.com/a.mp4", filename: "a.mp4")
    pdf = video(transcript_status: nil, url: "https://example.com/a.pdf", filename: "a.pdf")

    assert_enqueued_jobs 3, only: KbTranscriptJob do
      KbTranscriptJob.sweep
    end
    assert_equal "pending", old.reload.transcript_status
    assert_equal "pending", site.reload.transcript_status
    assert_equal "awaiting_audio", direct.reload.transcript_status
    assert_nil pdf.reload.transcript_status
    assert_in_delta Time.current, stale.reload.updated_at, 5
    assert_equal "pending", fresh.reload.transcript_status
  end
end
