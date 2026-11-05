require "test_helper"

class KbTranscriptsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-transcripts-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    File.binwrite(File.join(@kb_dir, "talk.mp4"), "x")
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
    FileUtils.rm_rf(Kb::Transcript.state_dir)
  end

  test "dropped-in media with a sidecar vtt serves selectable cues" do
    File.write(File.join(@kb_dir, "talk.vtt"), "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nhello there\n")

    get kb_transcript_path(src: 0, file: "talk.mp4")

    body = response.parsed_body
    assert_equal [ "ready", "sidecar", false ], [ body["status"], body["source"], body["can_transcribe"] ]
    assert_equal [ { "start" => 1.0, "end" => 3.0, "text" => "hello there" } ], body["cues"]
  end

  test "downloaded captions are the fallback source" do
    @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://example.com/talk.mp4", status: "done",
                               filename: "talk.mp4", transcript: "00:00 - first\n01:30 - second\n", transcript_status: "done")

    get kb_transcript_path(src: 0, file: "talk.mp4")

    assert_equal "captions", response.parsed_body["source"]
    assert_equal 2, response.parsed_body["cues"].size
  end

  test "no transcript yet reports none and whether transcribing is possible" do
    get kb_transcript_path(src: 0, file: "talk.mp4")
    assert_equal "none", response.parsed_body["status"]
    assert_equal Kb::Transcript.available?, response.parsed_body["can_transcribe"]
  end

  test "transcribe queues one local job and marks the awaiting_audio download" do
    download = @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://example.com/talk.mp4", status: "done",
                                          filename: "talk.mp4", transcript_status: "awaiting_audio")
    Kb::Transcript.stub(:available?, true) do
      assert_enqueued_jobs 1, only: KbTranscribeJob do
        post kb_transcript_path, params: { src: 0, file: "talk.mp4" }
        post kb_transcript_path, params: { src: 0, file: "talk.mp4" } # already running
      end
    end

    assert_response :accepted
    assert_equal "running", response.parsed_body["status"]
    assert_equal "transcribing", download.reload.transcript_status
  end

  test "transcribe without whisper is a clear error" do
    Kb::Transcript.stub(:available?, false) do
      post kb_transcript_path, params: { src: 0, file: "talk.mp4" }
    end
    assert_response :unprocessable_content
  end

  test "rejects non-media, traversal and missing files" do
    File.write(File.join(@kb_dir, "n.md"), "x")
    get kb_transcript_path(src: 0, file: "n.md")
    assert_response :not_found
    get kb_transcript_path(src: 0, file: "../x.mp4")
    assert_response :not_found
  end

  test "media page renders the transcript panel for video and audio" do
    File.binwrite(File.join(@kb_dir, "song.mp3"), "x")
    get kb_file_path(src: 0, file: "talk.mp4")
    assert_select "[data-controller~=kb-transcript] .kb-transcript"
    get kb_file_path(src: 0, file: "song.mp3")
    assert_select ".kb-audio-view[data-controller~=kb-transcript] audio.kb-selectable-media"
    assert_select "[data-controller~=kb-media-copy]"
  end
end
