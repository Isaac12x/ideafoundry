require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = { "Authorization" => "Bearer webhook-secret" }
  end

  test "create_idea webhook returns a temporary idea id" do
    Rails.application.credentials.stub(:dig, "webhook-secret") do
      assert_difference "Submission.count", 1 do
        post webhooks_external_url,
             params: {
               event: "create_idea",
               payload: {
                 title: "Webhook gateway idea",
                 source: "openclaw_gateway"
               },
               content: "First gateway note"
             },
             headers: @headers
      end

      assert_response :accepted

      json = JSON.parse(response.body)

      assert_equal "queued", json["status"]
      assert_match(/\AIDEA-TMP-\d{8}-[A-Z0-9]{4}\z/, json["temporary_idea_id"])
    end
  end

  test "create_idea webhook appends to an existing intake item when temporary idea id is provided" do
    Rails.application.credentials.stub(:dig, "webhook-secret") do
      post webhooks_external_url,
           params: {
             event: "create_idea",
             payload: {
               title: "Webhook gateway idea",
               source: "openclaw_gateway"
             },
             content: "First gateway note"
           },
           headers: @headers

      temporary_idea_id = JSON.parse(response.body)["temporary_idea_id"]

      assert_no_difference "Submission.count" do
        post webhooks_external_url,
             params: {
               event: "create_idea",
               payload: {
                 temporary_idea_id: temporary_idea_id,
                 source: "openclaw_gateway"
               },
               content: "Second gateway note"
             },
             headers: @headers
      end

      submission = Submission.find_by_reference!(temporary_idea_id)
      assert_includes submission.body, "Second gateway note"

      assert_response :accepted
      assert_equal "updated", JSON.parse(response.body)["status"]
    end
  end
end
