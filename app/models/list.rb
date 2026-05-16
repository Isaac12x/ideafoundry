class List < ApplicationRecord
  KINDS = %w[kanban named].freeze

  belongs_to :user
  has_many :idea_lists, -> { order(:position) }, dependent: :destroy
  has_many :ideas, through: :idea_lists

  # Validations
  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :position, presence: true, uniqueness: { scope: [:user_id, :kind] }

  # Callbacks
  before_validation :set_kind
  before_validation :set_position, on: :create

  # Scopes
  scope :ordered, -> { order(:position) }
  scope :kanban, -> { where(kind: "kanban") }
  scope :named, -> { where(kind: "named") }

  def kanban?
    kind == "kanban"
  end

  def named?
    kind == "named"
  end

  private

  def set_kind
    self.kind = "kanban" if kind.blank?
  end

  def set_position
    return if position.present? || user.nil?
    
    max_position = user.lists.where(kind: kind).maximum(:position) || 0
    self.position = max_position + 1
  end
end
