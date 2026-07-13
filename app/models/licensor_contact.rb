class LicensorContact < ApplicationRecord
  belongs_to :licensor

  enum :channel, {
    email: 0,
    call: 1,
    meeting: 2,
    note: 3,
    other: 4
  }

  validates :occurred_at, presence: true
  validates :channel, presence: true

  before_validation :default_occurred_at, on: :create
  after_commit :refresh_licensor_last_contacted

  CHANNEL_LABELS = {
    "email"   => "Email",
    "call"    => "Call",
    "meeting" => "Meeting",
    "note"    => "Note",
    "other"   => "Other"
  }.freeze

  def channel_label
    CHANNEL_LABELS[channel.to_s] || channel.to_s.humanize
  end

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end

  def refresh_licensor_last_contacted
    licensor.refresh_last_contacted!
  end
end
