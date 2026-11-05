# User-scoped label for grouping ideas (e.g. "Productizing"). Many-to-many with ideas.
class Theme < ApplicationRecord
  belongs_to :user
  has_many :idea_themes, dependent: :destroy
  has_many :ideas, through: :idea_themes

  # Swatches = app tokens (accent, info, success, danger, warning) + a violet.
  PALETTE_NAMES = {
    "#d4953a" => "Amber", "#60a5fa" => "Sky", "#34d399" => "Mint",
    "#f87171" => "Coral", "#fbbf24" => "Gold", "#a78bfa" => "Violet"
  }.freeze
  PALETTE = PALETTE_NAMES.keys.freeze

  validates :name, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :color, format: { with: /\A#\h{6}\z/ }, allow_blank: true

  before_validation { self.name = name.to_s.squish }

  scope :ordered, -> { order(Arel.sql("LOWER(name)")) }

  # Existing theme (case-insensitive) or a new one; used for create-on-the-fly.
  def self.for_name(user, name)
    name = name.to_s.squish
    return if name.blank?

    user.themes.where("LOWER(name) = ?", name.downcase).first || user.themes.create(name: name)
  end
end
