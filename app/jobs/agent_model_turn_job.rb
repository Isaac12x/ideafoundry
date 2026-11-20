# Answers a thread turn addressed to the "model" agent: one local-inference call with the thread so far as context.
class AgentModelTurnJob < ApplicationJob
  queue_as :default

  def perform(question_id)
    question = AgentEvent.find_by(id: question_id, event_type: "question")
    return unless question
    return if question.user.agent_events.exists?(event_type: "answer", target: question)

    text = question.question_prompt
    history = question.agent_thread&.history(before: question).presence
    answer, error =
      begin
        [ LocalAgent::PromptClient.new.call(instruction: text, context: history || "(none)"), false ]
      rescue LocalAgent::PromptClient::Error => e
        [ e.message, true ]
      end

    question.user.agent_events.create!(
      event_type: "answer", target: question, agent_thread: question.agent_thread, summary: answer.truncate(160),
      payload: { "answer" => answer, "agent" => "model", "error" => error }
    )
  end
end
