class BuildItem < ApplicationRecord
  belongs_to :user

  validates :title, presence: true

  # Store links as JSON array of {url, label} objects
  serialize :links, coder: JSON

  def links
    super || []
  end

  scope :pending, -> { where(completed: false).order(:position) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  before_validation :set_position, on: :create

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
  end

  private

  def set_position
    return if position.present? || user.nil?
    max = user.build_items.maximum(:position) || 0
    self.position = max + 1
  end
end
