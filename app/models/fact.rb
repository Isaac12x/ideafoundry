class Fact < ApplicationRecord
  include SemanticIndexable
  semantic_index type: "fact", owner: ->(r) { r.user_id }, sections: ->(r) { [ r.body ] }
  belongs_to :user

  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
