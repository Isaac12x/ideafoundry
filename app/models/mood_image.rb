class MoodImage < ApplicationRecord
  belongs_to :user
  belongs_to :idea, optional: true
  has_one_attached :file

  validate :file_attached

  # z_index doubles as the presentation order; created_at breaks ties.
  scope :ordered, -> { order(:z_index, :created_at) }
  # The global board (KB tab) is everything not tied to a specific idea.
  scope :global, -> { where(idea_id: nil) }

  private

  def file_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
