# A request for the Chrome extension to capture a page into the KB.
# The extension claims/completes jobs over Api::V1::CaptureController.
class CaptureJob < ApplicationRecord
  STATES = %w[queued running completed failed].freeze
  FORMATS = %w[md pdf].freeze
  ACTIVE_LIMIT = 100
  TIMEOUT = 5.minutes
  TIMEOUT_ERROR = "Worker timed out. Check the KB before submitting again."

  # Conversations only the signed-in browser can fetch; KB "Download from URL" routes these here.
  EXTENSION_HOSTS = %w[chatgpt.com chat.openai.com claude.ai].freeze

  belongs_to :user

  before_validation { self.public_id ||= SecureRandom.uuid }

  validates :url, presence: true, length: { maximum: 2048 }
  validate :url_is_http
  validates :file_format, inclusion: { in: FORMATS }
  validates :state, inclusion: { in: STATES }
  validate :queue_not_full, on: :create

  scope :active, -> { where(state: %w[queued running]) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.extension_url?(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTP) && EXTENSION_HOSTS.include?(uri.host.to_s.downcase.delete_prefix("www."))
  rescue URI::InvalidURIError
    false
  end

  # Lazy, like the reference queue: running jobs past the timeout fail.
  def self.expire_stale!
    where(state: "running").where("claimed_at < ?", TIMEOUT.ago)
      .update_all(state: "failed", error: TIMEOUT_ERROR, updated_at: Time.current)
  end

  # Oldest queued job -> running. Conditional update makes concurrent claims safe.
  def self.claim_next!(user)
    user.capture_jobs.where(state: "queued").order(:created_at, :id).each do |job|
      won = where(id: job.id, state: "queued").update_all(state: "running", claimed_at: Time.current, updated_at: Time.current)
      return job.reload if won == 1
    end
    nil
  end

  def finish!(state:, filename: nil, error: nil)
    update!(state: state, finished_at: Time.current,
            filename: filename.is_a?(String) ? filename.first(250) : nil,
            error: error.is_a?(String) ? error.first(1000) : nil)
  end

  def as_extension_json
    {
      id: public_id, url: url, format: file_format, state: state,
      createdAt: ms(created_at), claimedAt: ms(claimed_at), finishedAt: ms(finished_at),
      filename: filename, error: error,
      source: source_index, directory: dir
    }.compact
  end

  private

  def ms(time) = time && (time.to_f * 1000).to_i

  def url_is_http
    uri = URI.parse(url.to_s)
    errors.add(:url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "must be an http(s) URL")
  end

  def queue_not_full
    errors.add(:base, "Queue is full") if user && user.capture_jobs.active.count >= ACTIVE_LIMIT
  end
end
