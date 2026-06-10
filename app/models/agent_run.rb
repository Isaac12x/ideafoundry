class AgentRun < ApplicationRecord
  STALE_AFTER = 2.minutes

  belongs_to :user
  has_many :agent_events, dependent: :nullify

  serialize :metadata, coder: JSON

  enum :status, {
    starting: 0,
    running: 1,
    stopped: 2,
    failed: 3,
    stale: 4
  }

  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> {
    where(status: [statuses.fetch("starting"), statuses.fetch("running")])
      .where(
        "(last_heartbeat_at IS NULL AND created_at >= ?) OR last_heartbeat_at >= ?",
        STALE_AFTER.ago,
        STALE_AFTER.ago
      )
  }

  def heartbeat!(payload = {})
    update!(
      status: :running,
      last_heartbeat_at: Time.current,
      metadata: (metadata || {}).merge(payload)
    )
  end

  def stop!
    update!(status: :stopped, stopped_at: Time.current)
  end

  def heartbeat_stale?
    return false unless starting? || running?

    timestamp = last_heartbeat_at || created_at
    timestamp.present? && timestamp < STALE_AFTER.ago
  end
end
