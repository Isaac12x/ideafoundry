class IdeaTheme < ApplicationRecord
  belongs_to :idea
  belongs_to :theme
  validates :theme_id, uniqueness: { scope: :idea_id }
end
