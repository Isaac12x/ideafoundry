class AgentRecommendation < ApplicationRecord
  belongs_to :user
  belongs_to :agent_event, optional: true
  belongs_to :target, polymorphic: true, optional: true

  serialize :payload, coder: JSON

  enum :status, {
    pending: 0,
    approved: 1,
    dismissed: 2,
    applied: 3,
    failed: 4
  }

  validates :action, presence: true
  validates :risk_level, presence: true, inclusion: { in: %w[low medium high] }

  scope :recent, -> { order(created_at: :desc) }

  def approve!
    result = LocalAgent::Toolbox.new(
      user: user,
      agent_run: agent_event&.agent_run,
      review_override: true
    ).call(action, (payload || {}).merge("recommendation_id" => id))

    if result[:ok]
      update!(status: :applied, reviewed_at: Time.current)
      true
    else
      update!(
        status: :failed,
        reviewed_at: Time.current,
        payload: (payload || {}).merge("last_error" => result[:error], "last_result" => result)
      )
      false
    end
  end

  def dismiss!
    update!(status: :dismissed, reviewed_at: Time.current)
  end
end
