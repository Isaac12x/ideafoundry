require "test_helper"

class LocalAgentPromptClientTest < ActiveSupport::TestCase
  test "rejects remote inference endpoints to keep KB context local" do
    error = assert_raises(LocalAgent::PromptClient::Error) do
      LocalAgent::PromptClient.new(base_url: "https://example.com/v1")
    end

    assert_match(/local inference endpoint/i, error.message)
  end

  test "accepts the bundled local inference endpoint" do
    assert_nothing_raised do
      LocalAgent::PromptClient.new(base_url: "http://127.0.0.1:8080/v1")
    end
  end
end
