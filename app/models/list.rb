class List < ApplicationRecord
  KINDS = %w[kanban named].freeze

  belongs_to :user
  belongs_to :kanban_board, optional: true
  has_many :idea_lists, -> { order(:position) }, dependent: :destroy
  has_many :ideas, through: :idea_lists

  # Validations
  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :kanban_board, presence: true, if: :kanban?
  validates :position, presence: true
  validates :position, uniqueness: { scope: :kanban_board_id }, if: :kanban?
  validates :position, uniqueness: { scope: [:user_id, :kind] }, if: :named?
  validate :kanban_board_belongs_to_user

  # Callbacks
  before_validation :set_kind
  before_validation :set_kanban_board
  before_validation :clear_kanban_board_for_named
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

  def set_kanban_board
    return unless kanban? && user.present? && kanban_board.blank?

    self.kanban_board = user.default_kanban_board
  end

  def clear_kanban_board_for_named
    self.kanban_board = nil if named?
  end

  def set_position
    return if position.present? || user.nil?

    max_position =
      if kanban? && kanban_board.present?
        kanban_board.lists.maximum(:position)
      else
        user.lists.where(kind: kind).maximum(:position)
      end

    self.position = max_position.to_i + 1
  end

  def kanban_board_belongs_to_user
    return if kanban_board.blank? || user.blank? || kanban_board.user_id == user_id

    errors.add(:kanban_board, "must belong to the list owner")
  end
end
