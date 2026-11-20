class TodoItem < ApplicationRecord
  include SemanticIndexable
  semantic_index type: "todo", owner: ->(r) { r.user_id || r.idea&.user_id }, sections: ->(r) { [ r.title ] }, parents: ->(r) { [ r.idea ] }
  include RecordsIdeaHistory
  include NotificationScope

  belongs_to :idea, optional: true
  belongs_to :user, optional: true # general and project tasks; idea tasks reach the user through the idea

  validates :title, presence: true, length: { maximum: 255 }

  scope :pending, -> { where(completed: false).order(:position) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  validate :scope_has_owner
  scope :visible_to, ->(user) { where(user_id: user.id).or(where(idea_id: user.ideas.select(:id))) }

  before_validation :set_position, on: :create
  records_idea_history as: "todo"

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
  end

  private

  def scope_has_owner
    errors.add(:base, "needs an idea or a user") unless idea_id || user_id
  end

  def set_position
    return if position.present?
    siblings = TodoItem.where(idea_id: idea_id, user_id: user_id, project_src: project_src, project_path: project_path)
    self.position = (siblings.maximum(:position) || 0) + 1
  end
end
