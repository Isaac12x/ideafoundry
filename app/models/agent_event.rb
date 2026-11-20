class AgentEvent < ApplicationRecord
  belongs_to :user
  belongs_to :agent_run, optional: true
  belongs_to :agent_thread, optional: true, touch: true
  belongs_to :target, polymorphic: true, optional: true

  serialize :payload, coder: JSON

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # A question as the agent should read it: the optional idea context (kept out of the visible thread) then the user's words.
  def question_prompt
    [ payload&.dig("context").presence, payload&.dig("question").presence || summary ].compact.join("\n\n")
  end
end
