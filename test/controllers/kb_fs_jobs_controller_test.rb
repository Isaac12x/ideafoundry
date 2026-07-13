require "test_helper"

class KbFsJobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-job-controller-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "research"))
    File.write(File.join(@kb_dir, "research", "brief.md"), "# Brief")
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [@kb_dir], "hide_native" => true }
    ))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "queues a filesystem-scoped AI job and renders it in the target folder" do
    assert_enqueued_with(job: KbFsJobRunnerJob) do
      post kb_fs_jobs_path,
           params: {
             src: 0,
             path: "research/brief.md",
             context_kind: "file",
             prompt: "Find the missing evidence"
           },
           as: :turbo_stream
    end

    assert_response :success
    task = @user.kb_fs_jobs.last
    assert_equal File.expand_path(@kb_dir), task.source_path
    assert_equal "research", task.target_dir
    assert_equal "research/brief.md", task.context_path
    assert_select ".kb-job-row", text: /Find the missing evidence/
    assert @user.agent_events.where(event_type: "kb_job_queued").exists?
  end

  test "accepts an audio request for FluidVoice transcription" do
    voice = Rack::Test::UploadedFile.new(StringIO.new("webm bytes"), "audio/webm", original_filename: "request.webm")

    post kb_fs_jobs_path,
         params: {
           src: 0,
           path: "research",
           context_kind: "folder",
           voice_message: voice
         },
         as: :turbo_stream

    assert_response :success
    task = @user.kb_fs_jobs.last
    assert task.voice_message.attached?
    assert_equal "research", task.target_dir
  end

  test "requires a typed or voice request" do
    post kb_fs_jobs_path,
         params: { src: 0, path: "research", context_kind: "folder", prompt: "" },
         as: :turbo_stream

    assert_response :unprocessable_content
    assert_no_enqueued_jobs only: KbFsJobRunnerJob
  end

  test "rejects context traversal" do
    post kb_fs_jobs_path,
         params: { src: 0, path: "../outside", context_kind: "folder", prompt: "Review" },
         as: :turbo_stream

    assert_response :unprocessable_content
    assert_empty @user.kb_fs_jobs
  end
end
