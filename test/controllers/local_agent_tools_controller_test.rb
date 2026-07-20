require "test_helper"

class LocalAgentToolsControllerTest < ActionDispatch::IntegrationTest
  test "GET local agent tools returns bridge discovery" do
    get "/local-agent/tools", as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("ok")
    assert_includes body.fetch("tool_names"), "get_settings"
    assert_includes body.fetch("tool_names"), "record_event"
    assert_equal "/local-agent/tools/:tool_name", body.dig("invocation", "path")
  end

  test "POST local agent tools without tool payload returns bridge discovery" do
    post "/local-agent/tools", params: {}, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("ok")
    assert_includes body.fetch("tools").map { |tool| tool.fetch("name") }, "list_work"
  end

  test "POST local agent tools can dispatch a compact tool call" do
    post "/local-agent/tools", params: { tool_name: "get_settings", arguments: {} }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("ok")
    assert body.key?("settings")
    assert body.key?("status")
  end

  test "heartbeat event via run-id header updates the agent run" do
    user = User.first || User.create!(email: "user@example.com", name: "Default User")
    original = user.settings.deep_dup
    user.update_local_agent_settings("enabled" => true)
    run = user.agent_runs.create!(status: :starting, started_at: 1.hour.ago, last_heartbeat_at: 1.hour.ago)

    post "/local-agent/tools/record_event",
         params: { event_type: "heartbeat", summary: "cycle started" },
         headers: { "X-Idea-Foundry-Agent-Run-Id" => run.id.to_s },
         as: :json

    assert_response :success
    assert_equal true, response.parsed_body.fetch("ok")
    run.reload
    assert_equal "running", run.status
    assert run.last_heartbeat_at > 1.minute.ago, "heartbeat should refresh last_heartbeat_at"
    assert_equal run.id, AgentEvent.where(event_type: "heartbeat").recent.first.agent_run_id
  ensure
    user.update!(settings: original) if original
  end

  test "write_kb creates a KB file the agent can list and read back" do
    user = User.first || User.create!(email: "user@example.com", name: "Default User")
    original = user.settings.deep_dup
    dir = Rails.root.join("tmp", "kb-agent-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(dir)
    user.update_kb_folders([dir])
    user.update_local_agent_settings("enabled" => true)
    src = 1 # 0 is the native App KB source

    post "/local-agent/tools", params: { tool_name: "write_kb", arguments: { src: src, file: "research/agent-note", content: "hello from the agent" } }, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("ok")
    assert_equal "hello from the agent", File.read(File.join(dir, "research", "agent-note.md"))

    post "/local-agent/tools", params: { tool_name: "list_kb", arguments: {} }, as: :json
    assert_includes response.parsed_body.fetch("kb_files").map { |f| f["file"] }, "research/agent-note.md"

    post "/local-agent/tools", params: { tool_name: "read_kb", arguments: { src: src, file: "research/agent-note.md" } }, as: :json
    assert_equal "hello from the agent", response.parsed_body.dig("kb_file", "content")
  ensure
    user.update!(settings: original) if original
    FileUtils.rm_rf(dir) if dir
  end

  test "write_kb refuses path traversal outside the source" do
    user = User.first || User.create!(email: "user@example.com", name: "Default User")
    original = user.settings.deep_dup
    dir = Rails.root.join("tmp", "kb-agent-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(dir)
    user.update_kb_folders([dir])
    user.update_local_agent_settings("enabled" => true)

    post "/local-agent/tools", params: { tool_name: "write_kb", arguments: { src: 1, file: "../escape", content: "nope" } }, as: :json
    assert_response :unprocessable_content
    assert_equal false, response.parsed_body.fetch("ok")
    refute File.exist?(File.join(dir, "..", "escape.md"))
  ensure
    user.update!(settings: original) if original
    FileUtils.rm_rf(dir) if dir
  end

  test "write_kb is blocked when the local agent is disabled" do
    user = User.first || User.create!(email: "user@example.com", name: "Default User")
    original = user.settings.deep_dup
    user.update_local_agent_settings("enabled" => false)

    post "/local-agent/tools", params: { tool_name: "write_kb", arguments: { src: 0, file: "x", content: "y" } }, as: :json
    assert_response :unprocessable_content
    assert_equal "local_agent_disabled", response.parsed_body.fetch("error")
  ensure
    user.update!(settings: original) if original
  end
end
