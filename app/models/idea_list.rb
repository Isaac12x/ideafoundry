class IdeaList < ApplicationRecord
  belongs_to :idea
  belongs_to :list

  # Validations
  validates :position, presence: true
  validates :idea_id, uniqueness: { scope: :list_id }

  # Callbacks
  before_validation :set_position, on: :create

  # Scopes
  scope :ordered, -> { order(:position) }

  # Notifications
  after_create :notify_added_to_list

  private

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
