class IdeaList < ApplicationRecord
  include RecordsIdeaHistory

  belongs_to :idea
  belongs_to :list

  # Validations
  validates :position, presence: true
  validates :idea_id, uniqueness: { scope: :list_id, message: "is already in this list" }
  validate :single_kanban_list_per_idea
  validate :idea_meets_kanban_scoring_threshold

  # Callbacks
  before_validation :set_position, on: :create
  records_idea_history as: "list membership"

  # Scopes
  scope :ordered, -> { order(:position) }

  # Notifications
  after_create :notify_added_to_list

  private

  def single_kanban_list_per_idea
    return unless idea_id.present? && list&.kanban? && list.kanban_board_id.present?

    existing_kanban_memberships = IdeaList.joins(:list)
      .where(idea_id: idea_id, lists: { kind: "kanban", kanban_board_id: list.kanban_board_id })
    existing_kanban_memberships = existing_kanban_memberships.where.not(id: id) if id.present?
    return unless existing_kanban_memberships.where.not(list_id: list_id).exists?

    errors.add(:idea_id, "already has a kanban list")
  end

  def idea_meets_kanban_scoring_threshold
    return unless idea && list&.kanban?
    return if idea.kanban_eligible?

    errors.add(:idea, idea.kanban_ineligibility_message)
  end

  def notify_added_to_list
    user = idea&.user
    return unless user&.notification_enabled?("added_to_list")

    EventNotificationJob.perform_later(
      idea_id: idea_id,
      user_id: user.id,
      event_type: "added_to_list",
      metadata: { idea_title: idea.title, list_name: list.name }
    )
  end


  def set_position
    return if position.present? || list.nil?
    
    max_position = list.idea_lists.maximum(:position) || 0
    self.position = max_position + 1
  end
end
