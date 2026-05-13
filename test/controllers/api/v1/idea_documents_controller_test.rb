require "test_helper"

class Api::V1::IdeaDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @idea = ideas(:one)
    @idea.description = "Initial spec"
    @idea.save!
    @version = @idea.create_version("Initial version")
    @token = IdeaAgentToken.generate(idea: @idea, name: "Spec Bot")
    @headers = { "Authorization" => "Bearer #{@token.raw_token}" }
  end

  test "shows the idea document for a valid idea token" do
    get api_v1_idea_document_url(@idea), headers: @headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @idea.id, json["idea_id"]
    assert_equal "Mobile App for Local Farmers", json["title"]
    assert_equal "Initial spec", json["description"]
    assert_equal @version.id, json["latest_version_id"]
  end

  test "updates the idea document and records version history" do
    assert_difference -> { @idea.versions.count }, 1 do
      patch api_v1_idea_document_url(@idea),
            params: { description: "Revised spec", commit_message: "Tighten acceptance criteria" }.to_json,
            headers: @headers.merge("Content-Type" => "application/json")
    end

    assert_response :success
    @idea.reload
    assert_equal "Revised spec", @idea.description.to_plain_text
    assert_equal "Spec Bot: Tighten acceptance criteria", @idea.latest_version.commit_message
  end

  test "appends to the idea document and records version history" do
    patch api_v1_idea_document_url(@idea),
          params: { append: "Next iteration", commit_message: "Add next iteration" }.to_json,
          headers: @headers.merge("Content-Type" => "application/json")

    assert_response :success
    @idea.reload
    assert_equal "Initial spec\n\nNext iteration", @idea.description.to_plain_text
    assert_equal "Spec Bot: Add next iteration", @idea.latest_version.commit_message
  end

  test "rejects stale base version updates" do
    @idea.description = "Human edit"
    @idea.save!
    current = @idea.create_version("Human edit")

    patch api_v1_idea_document_url(@idea),
          params: { description: "Stale edit", base_version_id: @version.id }.to_json,
          headers: @headers.merge("Content-Type" => "application/json")

    assert_response :conflict
    assert_equal current.id, JSON.parse(response.body)["latest_version_id"]
  end

  test "does not allow a token to access another idea document" do
    other_idea = ideas(:two)

    get api_v1_idea_document_url(other_idea), headers: @headers

    assert_response :not_found
  end
end
