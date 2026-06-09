class Drawing < ApplicationRecord
  include RecordsIdeaHistory

  belongs_to :idea

  has_one_attached :rendered_png

  enum :role, { general: 0, hero: 1, attachment: 2 }, default: :general

  serialize :content, coder: JSON

  validates :title, presence: true
  validates :content, presence: true
  validate :only_one_hero_per_idea

  scope :ordered, -> { order(Arel.sql("COALESCE(position, 999999)"), updated_at: :desc) }

  records_idea_history as: "drawing"

  def png_url
    return nil unless rendered_png.attached?
    Rails.application.routes.url_helpers.rails_blob_path(rendered_png, only_path: true)
  end

  private

  def only_one_hero_per_idea
    return unless hero?
    other = idea.drawings.hero.where.not(id: id)
    errors.add(:role, "already used by another drawing on this idea") if other.exists?
  end
end
