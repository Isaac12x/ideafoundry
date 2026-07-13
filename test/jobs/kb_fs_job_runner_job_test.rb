require "test_helper"

class KbFsJobRunnerJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-job-runner-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "research"))
    File.write(File.join(@kb_dir, "research", "brief.md"), "# Brief\n\nKnown evidence")
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [@kb_dir], "hide_native" => true }
    ))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "writes successful AI output into job_results beside the context" do
    task = build_task(prompt: "Find gaps")
    fake_client = Object.new
    captured = nil
    fake_client.define_singleton_method(:call) do |instruction:, context:|
      captured = { instruction: instruction, context: context }
      "## Gaps\n\nAdd a primary source."
    end

    LocalAgent::PromptClient.stub(:new, ->(*) { fake_client }) do
      KbFsJobRunnerJob.perform_now(task.id)
    end

    task.reload
    assert task.done?
    assert_equal "Find gaps", captured[:instruction]
    assert_includes captured[:context], "Known evidence"
    assert_match(%r{\Aresearch/job_results/.+\.md\z}, task.result_path)
    result = File.read(File.join(@kb_dir, task.result_path))
    assert_includes result, "Add a primary source"
    assert @user.agent_events.where(event_type: "kb_job_completed").exists?
  end

  test "writes a visible error result when local inference fails" do
    task = build_task(prompt: "Summarise")
    fake_client = Object.new
    fake_client.define_singleton_method(:call) { |**| raise LocalAgent::PromptClient::Error, "model offline" }

    LocalAgent::PromptClient.stub(:new, ->(*) { fake_client }) do
      KbFsJobRunnerJob.perform_now(task.id)
    end

    task.reload
    assert task.failed?
    assert_includes task.error, "model offline"
    assert_match(/-error\.md\z/, task.result_path)
    assert_includes File.read(File.join(@kb_dir, task.result_path)), "model offline"
    assert @user.agent_events.where(event_type: "kb_job_failed").exists?
  end

  test "transcribes a voice message through FluidVoice before prompting the AI" do
    task = build_task(prompt: nil)
    task.voice_message.attach(io: StringIO.new("voice bytes"), filename: "request.webm", content_type: "audio/webm")
    fake_client = Object.new
    received_instruction = nil
    fake_client.define_singleton_method(:call) do |instruction:, context:|
      received_instruction = instruction
      "Voice result"
    end

    FluidVoiceClient.stub(:transcribe, { transcript: "Compare the evidence" }) do
      LocalAgent::PromptClient.stub(:new, ->(*) { fake_client }) do
        KbFsJobRunnerJob.perform_now(task.id)
      end
    end

    assert_equal "Compare the evidence", task.reload.transcript
    assert_equal "Compare the evidence", received_instruction
    assert task.done?
  end

  private

  def build_task(prompt:)
    @user.kb_fs_jobs.create!(
      source_index: 0,
      source_path: @kb_dir,
      context_path: "research/brief.md",
      context_kind: "file",
      target_dir: "research",
      prompt: prompt,
      status: "pending"
    )
  end
end
