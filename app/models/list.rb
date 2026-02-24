class List < ApplicationRecord
  belongs_to :user
  has_many :idea_lists, -> { order(:position) }, dependent: :destroy
  has_many :ideas, through: :idea_lists

  # Validations
  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :user_id }

  # Callbacks
  before_validation :set_position, on: :create

  # Scopes
  scope :ordered, -> { order(:position) }

  private

  def set_position
    return if position.present? || user.nil?
    
    max_position = user.lists.maximum(:position) || 0
    self.position = max_position + 1
  end
end
