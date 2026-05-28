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
end
