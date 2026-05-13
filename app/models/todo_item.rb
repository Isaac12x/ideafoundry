class TodoItem < ApplicationRecord
  include RecordsIdeaHistory

  belongs_to :idea

  validates :title, presence: true, length: { maximum: 255 }

  scope :pending, -> { where(completed: false).order(:position) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  before_validation :set_position, on: :create
  records_idea_history as: "todo"

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
  end

  private

  def set_position
    return if position.present?
    max = idea.todo_items.maximum(:position) || 0
    self.position = max + 1
  end
end
