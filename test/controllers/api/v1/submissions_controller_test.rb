require "test_helper"

class Api::V1::SubmissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @api_key = ApiKey.generate(user: @user, name: "Openclaw Gateway")
    @auth_headers = { "Authorization" => "Bearer #{@api_key.raw_token}" }
  end

  test "creates a submission and returns a temporary idea id" do
    assert_difference "Submission.count", 1 do
      post api_v1_submissions_url,
           params: {
             title: "Gateway idea",
             body: "Initial gateway note",
             source: "openclaw_gateway"
           }.to_json,
           headers: @auth_headers.merge("Content-Type" => "application/json")
    end

    assert_response :created

    json = JSON.parse(response.body)

    assert_equal "created", json["action"]
    assert_equal "submission", json["target"]
    assert_match(/\AIDEA-TMP-\d{8}-[A-Z0-9]{4}\z/, json["temporary_idea_id"])
  end

  test "appends to an existing submission via temporary idea id and can fetch it by that id" do
    post api_v1_submissions_url,
         params: {
           title: "Gateway idea",
           body: "Initial gateway note",
           source: "openclaw_gateway"
         }.to_json,
         headers: @auth_headers.merge("Content-Type" => "application/json")

    temporary_idea_id = JSON.parse(response.body)["temporary_idea_id"]

    assert_no_difference "Submission.count" do
      post api_v1_submissions_url,
           params: {
             temporary_idea_id: temporary_idea_id,
             body: "Follow-up note from chat",
             source: "openclaw_gateway"
           }.to_json,
           headers: @auth_headers.merge("Content-Type" => "application/json")
    end

    assert_response :success

    submission = Submission.find_by_reference!(temporary_idea_id)
    assert_includes submission.body, "Follow-up note from chat"

    get api_v1_submission_url(temporary_idea_id), headers: @auth_headers

    assert_response :success

    json = JSON.parse(response.body)
    assert_equal temporary_idea_id, json["temporary_idea_id"]
    assert_equal submission.id, json["id"]
  end
end
