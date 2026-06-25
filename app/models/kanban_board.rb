class KanbanBoard < ApplicationRecord
  include TracksActivity
  tracks_activity

  belongs_to :user
  has_many :lists, -> { kanban.ordered }, dependent: :destroy

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :user_id }

  before_validation :set_position, on: :create

  scope :ordered, -> { order(:position) }

  private

  def set_position
    return if position.present? || user.nil?

    self.position = user.kanban_boards.maximum(:position).to_i + 1
  end
end
