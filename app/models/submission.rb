class Submission < ApplicationRecord
  include TracksActivity
  tracks_activity name_method: :title, ignore_fields: [:raw_data, :reviewed_at]

  INTAKE_REFERENCE_PREFIX = "IDEA-TMP".freeze

  belongs_to :user
  belongs_to :idea, optional: true
  has_many_attached :files
  has_rich_text :processed_body

  enum :status, { pending: 0, approved: 1, rejected: 2, expired: 3 }
  enum :priority, { low: 0, normal: 1, high: 2 }

  before_validation :normalize_intake_reference
  before_validation :ensure_intake_reference, on: :create

  validates :title, presence: true
  validates :intake_reference, presence: true, uniqueness: true
  validates :source_reference, uniqueness: { scope: :source }, allow_nil: true

  serialize :raw_data, coder: JSON

  scope :by_source, ->(source) { where(source: source) if source.present? }
  scope :by_priority, ->(priority) { where(priority: priority) if priority.present? }
  scope :by_reference, ->(reference) { where(intake_reference: normalize_reference_value(reference)) if reference.present? }
  scope :recent, -> { order(created_at: :desc) }
  scope :stale, -> { pending.where("created_at < ?", 30.days.ago) }

  class << self
    def normalize_reference_value(reference)
      reference.to_s.strip.upcase
    end

    def find_by_reference(reference)
      return if reference.blank?

      find_by(intake_reference: normalize_reference_value(reference))
    end

    def find_by_reference!(reference)
      find_by_reference(reference) || raise(ActiveRecord::RecordNotFound, "Submission not found")
    end
  end

  def temporary_idea_id
    intake_reference
  end

  def append_intake_update!(title: nil, body: nil, source: nil, source_reference: nil, priority: nil, raw_payload: nil)
    self.title = title if title.present?
    self.body = append_body(body)
    self.source = source if source.present? && self.source.blank?
    self.source_reference = source_reference if source_reference.present? && self.source_reference.blank?
    self.priority = priority if priority.present? && self.class.priorities.key?(priority.to_s)
    self.raw_data = merged_raw_data(raw_payload, source:, source_reference:, title:, body:, target: "submission")

    if rejected? || expired?
      self.status = :pending
      self.review_notes = nil
      self.reviewed_at = nil
    end

    save!
  end

  def record_intake_event!(title: nil, body: nil, source: nil, source_reference: nil, raw_payload: nil, target: nil)
    self.source = source if source.present? && self.source.blank?
    self.source_reference = source_reference if source_reference.present? && self.source_reference.blank?
    self.raw_data = merged_raw_data(raw_payload, source:, source_reference:, title:, body:, target:)
    save!
  end

  def reject!(notes = nil)
    update!(
      status: :rejected,
      review_notes: notes,
      reviewed_at: Time.current
    )
  end

  def reopen!
    update!(
      status: :pending,
      review_notes: nil,
      reviewed_at: nil
    )
  end

  private

  def append_body(new_body)
    cleaned_body = new_body.to_s.strip
    return body if cleaned_body.blank?

    [body.presence, cleaned_body].compact.join("\n\n---\n\n")
  end

  def merged_raw_data(raw_payload, source:, source_reference:, title:, body:, target:)
    data = case raw_data
           when Hash
             raw_data.deep_dup
           when nil
             {}
           else
             { "legacy_payload" => raw_data }
           end

    data["events"] ||= []
    data["events"] << {
      "received_at" => Time.current.iso8601,
      "source" => source.presence || self.source,
      "source_reference" => source_reference.presence || self.source_reference,
      "title" => title.presence || self.title,
      "body_present" => body.present?,
      "target" => target,
      "payload" => raw_payload
    }.compact
    data["last_payload"] = raw_payload if raw_payload.present?
    data
  end

  def ensure_intake_reference
    return if intake_reference.present?

    self.intake_reference = loop do
      candidate = "#{INTAKE_REFERENCE_PREFIX}-#{Time.current.strftime("%Y%m%d")}-#{SecureRandom.alphanumeric(4).upcase}"
      break candidate unless self.class.exists?(intake_reference: candidate)
    end
  end

  def normalize_intake_reference
    self.intake_reference = self.class.normalize_reference_value(intake_reference) if intake_reference.present?
  end
end
