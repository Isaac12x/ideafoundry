require "test_helper"

class LocalAgent::ToolboxTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user.update!(settings: {})
    @idea = @user.ideas.create!(
      title: "Local Agent Target",
      state: :idea_new,
      description: "Thin starting description"
    )
  end

  test "mutating tools reject writes while local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")

    assert_no_difference "Note.count" do
      result = toolbox.call("create_note", {
        "idea_id" => @idea.id,
        "body" => "Add context from the local agent"
      })

      assert_equal false, result.fetch(:ok)
      assert_equal "local_agent_disabled", result.fetch(:error)
    end
  end

  test "destructive tools create recommendations when destructive autonomy is disabled" do
    @user.update_local_agent_settings("enabled" => "1", "destructive_actions_enabled" => "0")
    submission = @user.submissions.create!(title: "Duplicate submission", body: "Already covered")

    assert_difference "AgentRecommendation.count", 1 do
      result = toolbox.call("reject_submission", {
        "submission_id" => submission.id,
        "review_notes" => "Duplicate of an existing idea",
        "reasoning" => "The payload appears to duplicate current work."
      })

      assert_equal true, result.fetch(:ok)
      assert_equal "recommended", result.fetch(:status)
      assert result.fetch(:recommendation_id)
    end

    assert submission.reload.pending?
    recommendation = AgentRecommendation.order(:created_at).last
    assert_equal @user, recommendation.user
    assert_equal "Submission", recommendation.target_type
    assert_equal submission.id, recommendation.target_id
    assert_equal "reject_submission", recommendation.action
    assert_equal "high", recommendation.risk_level
    assert_equal "pending", recommendation.status
    assert_equal "Duplicate of an existing idea", recommendation.payload["review_notes"]
  end

  test "destructive tools apply directly when destructive autonomy is enabled" do
    @user.update_local_agent_settings("enabled" => "1", "destructive_actions_enabled" => "1")
    submission = @user.submissions.create!(title: "Reject directly", body: "No longer useful")

    assert_no_difference "AgentRecommendation.count" do
      result = toolbox.call("reject_submission", {
        "submission_id" => submission.id,
        "review_notes" => "Outside the current product direction"
      })

      assert_equal true, result.fetch(:ok)
      assert_equal "rejected", result.dig(:submission, :status)
    end

    assert submission.reload.rejected?
    assert_equal "Outside the current product direction", submission.review_notes
  end

  test "idea updates create a single normal history version" do
    @user.update_local_agent_settings("enabled" => "1")

    assert_difference -> { @idea.versions.count }, 1 do
      result = toolbox.call("update_idea", {
        "idea_id" => @idea.id,
        "description" => "A stronger local-agent description.",
        "commit_message" => "Local agent: improve description"
      })

      assert_equal true, result.fetch(:ok)
    end

    @idea.reload
    assert_equal "A stronger local-agent description.", @idea.description.to_plain_text.strip
    assert_equal "Local agent: improve description", @idea.latest_version.commit_message
  end

  test "list work returns prioritized candidates across app surfaces" do
    @user.update_local_agent_settings("enabled" => "1")
    submission = @user.submissions.create!(title: "High priority intake", priority: :high)
    build_item = @user.build_items.create!(title: "Stale build detail", description: "- [ ] Fill in acceptance criteria")

    result = toolbox.call("list_work")

    assert_equal true, result.fetch(:ok)
    work = result.fetch(:work)
    assert work.any? { |item| item[:target_type] == "Submission" && item[:target_id] == submission.id }
    assert work.any? { |item| item[:target_type] == "Idea" && item[:target_id] == @idea.id }
    assert work.any? { |item| item[:target_type] == "BuildItem" && item[:target_id] == build_item.id }
  end

  test "list work prioritizes unanswered local agent questions" do
    @user.update_local_agent_settings("enabled" => "1")
    question = @user.agent_events.create!(
      event_type: "question",
      summary: "What should I focus on next?",
      payload: { "question" => "What should I focus on next?" }
    )

    result = toolbox.call("list_work", { "limit" => 1 })

    assert_equal true, result.fetch(:ok)
    work = result.fetch(:work)
    assert_equal "AgentEvent", work.first[:target_type]
    assert_equal question.id, work.first[:target_id]
    assert_equal "User", work.first.dig(:payload, :context_record, :record_type)
    assert_equal @user.id, work.first.dig(:payload, :context_record, :record_id)
  end

  test "read record supports user database context" do
    @user.update_local_agent_settings("enabled" => "1")
    @user.facts.create!(body: "Focus follows validated demand.")

    result = toolbox.call("read_record", {
      "record_type" => "User",
      "record_id" => @user.id
    })

    assert_equal true, result.fetch(:ok)
    record = result.fetch(:record)
    assert_equal "User", record[:target_type]
    assert record[:ideas].any? { |idea| idea[:id] == @idea.id }
    assert record[:facts].any? { |fact| fact[:body] == "Focus follows validated demand." }
  end

  test "record event stores answers against agent questions" do
    @user.update_local_agent_settings("enabled" => "1")
    question = @user.agent_events.create!(
      event_type: "question",
      summary: "What needs attention?",
      payload: { "question" => "What needs attention?" }
    )

    assert_difference "AgentEvent.where(event_type: 'answer').count", 1 do
      result = toolbox.call("record_event", {
        "event_type" => "answer",
        "target_type" => "AgentEvent",
        "target_id" => question.id,
        "summary" => "The active idea needs a clearer next todo.",
        "payload" => {}
      })

      assert_equal true, result.fetch(:ok)
    end

    answer = AgentEvent.where(event_type: "answer").recent.first
    assert_equal question, answer.target
    assert_equal "The active idea needs a clearer next todo.", answer.payload["answer"]
  end

  private

  test "kb tools hide, refuse to read and refuse to write private project paths" do
    dir = Rails.root.join("tmp", "kb-toolbox-priv-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(dir, "proj"))
    File.write(File.join(dir, "proj", ".kb-project.yml"), "private: true\n")
    File.write(File.join(dir, "proj", "secret.md"), "secret")
    File.write(File.join(dir, "open.md"), "open")
    @user.update!(settings: { "kb" => { "folders" => [ dir ], "hide_native" => true } })
    @user.update_local_agent_settings("enabled" => "1")

    files = toolbox.call("list_kb").fetch(:kb_files).map { |e| e[:file] }
    assert_equal [ "open.md" ], files

    read = toolbox.call("read_kb", { "file" => "proj/secret.md" })
    assert_equal "invalid_arguments", read.fetch(:error)
    assert_match(/private project/, read.fetch(:details).to_s)

    write = toolbox.call("write_kb", { "file" => "proj/new.md", "content" => "x" })
    assert_equal "invalid_arguments", write.fetch(:error)
    refute File.exist?(File.join(dir, "proj", "new.md"))
  ensure
    FileUtils.rm_rf(dir)
  end

  test "media digest tools write, search and read transcripts" do
    @user.update_local_agent_settings("enabled" => "1")
    dl = @user.kb_downloads.create!(source_index: 0, url: "https://youtu.be/abc", title: "Talk", status: "done",
                                    transcript: "00:01 - hello", transcript_status: "done")

    assert_difference [ "MediaDigest.count", "AgentEvent.count" ], 1 do
      result = toolbox.call("write_media_digest", "kb_download_id" => dl.id, "body" => "- hello fact")
      assert result.fetch(:ok)
    end
    found = toolbox.call("search_media_digests", "query" => "hello").fetch(:media_digests)
    assert_equal [ dl.id ], found.map { |d| d[:kb_download_id] }
    assert_equal "00:01 - hello", toolbox.call("read_record", "target_type" => "KbDownload", "target_id" => dl.id).dig(:record, :transcript)
  end

  test "write_media_digest is rejected while disabled" do
    @user.update_local_agent_settings("enabled" => "0")
    dl = @user.kb_downloads.create!(source_index: 0, url: "https://youtu.be/abc", status: "done")
    assert_no_difference "MediaDigest.count" do
      assert_equal "local_agent_disabled", toolbox.call("write_media_digest", "kb_download_id" => dl.id, "body" => "x").fetch(:error)
    end
  end

  test "other users KbDownload is not found" do
    foreign = users(:two).kb_downloads.create!(source_index: 0, url: "https://youtu.be/zzz", status: "done")
    assert_equal "not_found", toolbox.call("read_record", "target_type" => "KbDownload", "target_id" => foreign.id).fetch(:error)
  end

  test "private-project transcripts and digests are invisible to the agent" do
    @user.update_local_agent_settings("enabled" => "1")
    dl = private_download
    MediaDigest.record!(user: @user, kb_download: dl, body: "- hello secret")

    assert_empty toolbox.call("search_media_digests", "query" => "hello").fetch(:media_digests)
    assert_equal "not_found", toolbox.call("read_record", "target_type" => "KbDownload", "target_id" => dl.id).fetch(:error)
    assert_no_difference "MediaDigest.count" do
      assert_equal "not_found", toolbox.call("write_media_digest", "kb_download_id" => dl.id, "body" => "x").fetch(:error)
    end
  ensure
    FileUtils.rm_rf(@base)
  end

  def private_download
    @base = Dir.mktmpdir
    Kb::Project.create!(base: @base, parent_rel: "", name: "Secret")
    @user.kb_downloads.create!(source_index: 0, source_path: @base, dir: "Secret", filename: "v.mp4", url: "https://youtu.be/sec",
                               title: "Hush", status: "done", transcript: "00:01 - hello", transcript_status: "done")
  end

  def toolbox
    LocalAgent::Toolbox.new(user: @user)
  end
end
