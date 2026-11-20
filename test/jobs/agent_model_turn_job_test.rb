require "test_helper"

class AgentModelTurnJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @thread = @user.agent_threads.create!(title: "T")
    prior = @user.agent_events.create!(event_type: "question", agent_thread: @thread, summary: "a?", payload: { "question" => "a?" })
    @user.agent_events.create!(event_type: "answer", agent_thread: @thread, target: prior, summary: "b", payload: { "answer" => "b" })
    @question = @user.agent_events.create!(event_type: "question", agent_thread: @thread, summary: "c?", payload: { "question" => "c?", "agent" => "model" })
  end

  test "answers in the thread with prior turns as context" do
    seen = nil
    client = Object.new
    client.define_singleton_method(:call) { |instruction:, context:| seen = [ instruction, context ]; "done" }

    LocalAgent::PromptClient.stub(:new, ->(*) { client }) { AgentModelTurnJob.perform_now(@question.id) }

    answer = @user.agent_events.find_by!(event_type: "answer", target: @question)
    assert_equal [ "done", "model", false ], [ answer.payload["answer"], answer.payload["agent"], answer.payload["error"] ]
    assert_equal @thread, answer.agent_thread
    assert_equal "c?", seen[0]
    assert_includes seen[1], "You: a?"
  end

  test "records the failure as an error answer" do
    client = Object.new
    client.define_singleton_method(:call) { |**| raise LocalAgent::PromptClient::Error, "unavailable" }

    LocalAgent::PromptClient.stub(:new, ->(*) { client }) { AgentModelTurnJob.perform_now(@question.id) }

    assert_equal true, @user.agent_events.find_by!(event_type: "answer", target: @question).payload["error"]
  end
end
