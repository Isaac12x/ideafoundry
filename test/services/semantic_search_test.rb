require "test_helper"

class SemanticSearchTest < ActiveSupport::TestCase
  test "disabled without SEMANTIC_SERVICE_URL" do
    ENV.stub(:[], nil) { assert_nil SemanticSearch.search(prefix: "u1:", query: "x") }
  end

  test "returns nil instead of raising when the service is unreachable" do
    ENV["SEMANTIC_SERVICE_URL"] = "http://127.0.0.1:1"
    assert_nil SemanticSearch.search(prefix: "u1:", query: "x")
    assert_nil SemanticSearch.upsert([ { id: "a", text: "b" } ])
  ensure
    ENV.delete("SEMANTIC_SERVICE_URL")
  end
end
