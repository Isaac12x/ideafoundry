class IdeaTheme < ApplicationRecord
  include SemanticIndexable
  semantic_index owner: ->(r) { r.idea&.user_id }, parents: ->(r) { [ r.idea ] } # link change reindexes the idea's theme names
  belongs_to :idea
  belongs_to :theme
  validates :theme_id, uniqueness: { scope: :idea_id }
end
