# idea comes AFTER prerequisite (idea builds on / requires prerequisite).
class IdeaDependency < ApplicationRecord
  belongs_to :idea
  belongs_to :prerequisite, class_name: "Idea"

  validates :prerequisite_id, uniqueness: { scope: :idea_id }
  validate :distinct_ideas_same_user

  private

  def distinct_ideas_same_user
    return unless idea && prerequisite
    errors.add(:prerequisite, "cannot be the idea itself") if idea_id == prerequisite_id
    errors.add(:prerequisite, "must belong to the same user") if idea.user_id != prerequisite.user_id
  end
end
