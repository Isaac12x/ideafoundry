class KbMediaEdit < ApplicationRecord
  STATUSES = %w[pending running done failed].freeze
  MEDIA_KINDS = %w[image video audio pdf embed long_doc generic].freeze

  belongs_to :user
  has_one_attached :replacement_file

  serialize :operations, coder: JSON

  validates :source_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_path, :relative_path, presence: true
  validates :media_kind, inclusion: { in: MEDIA_KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }

  def pending? = status == "pending"
  def running? = status == "running"
  def done? = status == "done"
  def failed? = status == "failed"
end
