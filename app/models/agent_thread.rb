# A conversation with the in-app agent: question/answer AgentEvents sharing agent_thread_id. Each turn picks its own agent.
class AgentThread < ApplicationRecord
  include SemanticIndexable
  semantic_index type: "agent_thread", owner: ->(r) { r.user_id },
                 sections: ->(r) { [ r.title, *r.agent_events.where(event_type: "question").order(:id).last(20).map(&:summary) ] }
  HISTORY_TURNS = 8
  HISTORY_CHARS = 1200

  belongs_to :user
  has_many :agent_events, dependent: :nullify

  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def self.title_for(question)
    question.to_s.squish.truncate(60)
  end

  # Prior turns as plain text for the next agent: "You: ... / Agent (label): ...". Unanswered turns are skipped.
  def history(before: nil, limit: HISTORY_TURNS)
    questions = agent_events.where(event_type: "question").order(:id)
    questions = questions.where(id: ...before.id) if before
    questions = questions.last(limit)
    answers = agent_events.where(event_type: "answer", target_type: "AgentEvent", target_id: questions.map(&:id)).order(:id).group_by(&:target_id)
    questions.filter_map do |question|
      answer = answers[question.id]&.last
      next unless answer

      [ "You: #{question.payload&.dig("question").presence || question.summary}",
        "Agent (#{LocalAgent::Agents.label(answer.payload&.dig("agent"))}): #{answer.payload&.dig("answer").presence || answer.summary}" ]
    end.flatten.join("\n\n").truncate(HISTORY_CHARS * limit)
  end
end
