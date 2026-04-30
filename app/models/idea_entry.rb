class IdeaEntry < ApplicationRecord
  belongs_to :idea

  enum :kind, { tool: 0, competitor: 1, potential_competitor: 2 }

  validates :name, presence: true
  validates :kind, presence: true

  before_create :set_position

  scope :ordered, -> { order(Arel.sql("COALESCE(position, 999999)"), :created_at) }

  KIND_LABELS = {
    "tool" => "Tools",
    "competitor" => "Competitors",
    "potential_competitor" => "Potential Competitors"
  }.freeze

  KIND_SINGULARS = {
    "tool" => "Tool",
    "competitor" => "Competitor",
    "potential_competitor" => "Potential Competitor"
  }.freeze

  def self.label_for(kind)
    KIND_LABELS[kind.to_s] || kind.to_s.humanize
  end

  def self.singular_for(kind)
    KIND_SINGULARS[kind.to_s] || kind.to_s.humanize
  end

  private

  def set_position
    return if position.present?
    max_pos = idea.idea_entries.where(kind: kind).maximum(:position) || 0
    self.position = max_pos + 1
  end
end
