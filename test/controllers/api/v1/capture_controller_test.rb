require "test_helper"

class Api::V1::CaptureControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = { "Authorization" => "Bearer #{ApiKey.generate(user: @user, name: "Ext").raw_token}" }
    @json = @headers.merge("Content-Type" => "application/json")
  end

  def enqueue(url = "https://example.com/a", format: nil)
    post "/api/v1/capture/jobs", params: { url: url, format: format }.compact.to_json, headers: @json
    response
  end

  test "requires bearer auth" do
    get "/api/v1/capture/health"
    assert_response :unauthorized
    post "/api/v1/capture/jobs/claim", headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end

  test "health ok and no-store" do
    get "/api/v1/capture/health", headers: @headers
    assert_response :success
    assert_equal({ "ok" => true }, response.parsed_body)
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "non-extension origin is forbidden, extension origin allowed" do
    get "/api/v1/capture/health", headers: @headers.merge("Origin" => "https://evil.com")
    assert_response :forbidden
    get "/api/v1/capture/health", headers: @headers.merge("Origin" => "chrome-extension://abc")
    assert_response :success
  end

  test "create validates and returns job shape" do
    enqueue("https://example.com/a", format: "pdf")
    assert_response :created
    body = response.parsed_body
    assert_equal %w[createdAt format id state url], body.keys.sort
    assert_equal [ "pdf", "queued" ], [ body["format"], body["state"] ]
    assert_kind_of Integer, body["createdAt"]

    enqueue("javascript:alert(1)")
    assert_response :bad_request
    assert_includes response.parsed_body["error"], "http"
    enqueue("https://example.com", format: "doc")
    assert_response :bad_request
    enqueue("https://example.com")
    assert_equal "md", response.parsed_body["format"]
  end

  test "create returns 429 when queue is full" do
    CaptureJob::ACTIVE_LIMIT.times { @user.capture_jobs.create!(url: "https://x.com") }
    enqueue
    assert_response :too_many_requests
  end

  test "show returns job or 404" do
    id = enqueue.parsed_body["id"]
    get "/api/v1/capture/jobs/#{id}", headers: @headers
    assert_response :success
    get "/api/v1/capture/jobs/missing", headers: @headers
    assert_response :not_found
    assert_equal "Job not found", response.parsed_body["error"]
  end

  test "claim is 204 when empty" do
    post "/api/v1/capture/jobs/claim", headers: @headers
    assert_response :no_content
    assert_empty response.body
  end

  test "claim returns source and directory" do
    @user.capture_jobs.create!(url: "https://chatgpt.com/c/a", source_index: 0, dir: "chats")
    post "/api/v1/capture/jobs/claim", headers: @headers
    assert_equal [ 0, "chats" ], response.parsed_body.values_at("source", "directory")
  end

  test "claim takes oldest first and marks running" do
    first = enqueue("https://example.com/1").parsed_body["id"]
    CaptureJob.find_by(public_id: first).update_columns(created_at: 1.hour.ago)
    second = enqueue("https://example.com/2").parsed_body["id"]
    post "/api/v1/capture/jobs/claim", headers: @headers
    assert_response :success
    assert_equal [ first, "running" ], response.parsed_body.values_at("id", "state")
    assert_kind_of Integer, response.parsed_body["claimedAt"]
    post "/api/v1/capture/jobs/claim", headers: @headers
    assert_equal second, response.parsed_body["id"]
  end

  test "complete: 400 bad state, 409 unclaimed, finishes, idempotent" do
    id = enqueue.parsed_body["id"]
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "completed" }.to_json, headers: @json
    assert_response :conflict
    post "/api/v1/capture/jobs/claim", headers: @headers
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "bogus" }.to_json, headers: @json
    assert_response :bad_request

    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "completed", filename: "f" * 300 }.to_json, headers: @json
    assert_response :success
    assert_equal "completed", response.parsed_body["state"]
    assert_equal 250, response.parsed_body["filename"].length
    assert_kind_of Integer, response.parsed_body["finishedAt"]

    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "failed", error: "x" }.to_json, headers: @json
    assert_response :success
    assert_equal "completed", response.parsed_body["state"]
  end

  test "complete truncates error to 1000" do
    id = enqueue.parsed_body["id"]
    post "/api/v1/capture/jobs/claim", headers: @headers
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "failed", error: "e" * 2000 }.to_json, headers: @json
    assert_equal 1000, response.parsed_body["error"].length
  end

  test "jobs are scoped to the key's user" do
    id = enqueue.parsed_body["id"]
    other = { "Authorization" => "Bearer #{ApiKey.generate(user: users(:two), name: "Other").raw_token}" }
    get "/api/v1/capture/jobs/#{id}", headers: other
    assert_response :not_found
    post "/api/v1/capture/jobs/claim", headers: other
    assert_response :no_content
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "completed" }.to_json, headers: other.merge("Content-Type" => "application/json")
    assert_response :not_found
  end

  test "stale running jobs expire on request" do
    id = enqueue.parsed_body["id"]
    post "/api/v1/capture/jobs/claim", headers: @headers
    CaptureJob.find_by(public_id: id).update_columns(claimed_at: 6.minutes.ago)
    get "/api/v1/capture/jobs/#{id}", headers: @headers
    assert_equal "failed", response.parsed_body["state"]
    assert_equal CaptureJob::TIMEOUT_ERROR, response.parsed_body["error"]
  end

  test "completing a capture broadcasts a fresh KB tree" do
    id = enqueue.parsed_body["id"]
    post "/api/v1/capture/jobs/claim", headers: @headers
    called = []
    original = Kb::TreeBroadcaster.method(:call)
    Kb::TreeBroadcaster.define_singleton_method(:call) { |user| called << user }
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "completed", filename: "x.md" }.to_json, headers: @json
    assert_equal [ @user ], called
    post "/api/v1/capture/jobs/#{id}/complete", params: { state: "completed" }.to_json, headers: @json
    assert_equal 1, called.size
  ensure
    Kb::TreeBroadcaster.define_singleton_method(:call, original)
  end
end
