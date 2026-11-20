require "test_helper"

class AgentThreadTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @thread = @user.agent_threads.create!(title: "T")
  end

  def turn(text, answer: nil, agent: "local", thread: @thread)
    q = @user.agent_events.create!(event_type: "question", agent_thread: thread, summary: text, payload: { "question" => text, "agent" => agent })
    @user.agent_events.create!(event_type: "answer", agent_thread: thread, target: q, summary: answer, payload: { "answer" => answer, "agent" => agent }) if answer
    q
  end

  test "history lists answered prior turns with the agent that replied" do
    turn("one?", answer: "uno")
    turn("two?", answer: "dos", agent: "model")
    current = turn("three?")
    turn("other thread?", answer: "no", thread: @user.agent_threads.create!(title: "O"))

    history = @thread.history(before: current)

    assert_equal "You: one?\n\nAgent (Local agent): uno\n\nYou: two?\n\nAgent (#{LocalAgent::Agents.label("model")}): dos", history
  end

  test "questions without a thread stay in the legacy bucket" do
    turn("old?", thread: nil)
    turn("new?")

    assert_equal [ "old?" ], @user.local_agent_question_threads(thread: nil).map { |t| t[:question].summary }
    assert_equal [ "new?" ], @user.local_agent_question_threads(thread: @thread).map { |t| t[:question].summary }
  end

  test "work discovery hands the runner thread history and skips model-agent questions" do
    turn("one?", answer: "uno")
    runner_q = turn("two?")
    turn("quick?", agent: "model")

    candidates = LocalAgent::WorkDiscovery.new(@user).list(limit: 100).select { |c| c[:target_type] == "AgentEvent" }

    assert_equal [ runner_q.id ], candidates.map { |c| c[:target_id] }
    assert_includes candidates.first[:payload][:thread_history], "Agent (Local agent): uno"
  end
end
