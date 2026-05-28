class AgentEvent < ApplicationRecord
  belongs_to :user
  belongs_to :agent_run, optional: true
  belongs_to :target, polymorphic: true, optional: true

  serialize :payload, coder: JSON

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
