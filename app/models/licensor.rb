class Licensor < ApplicationRecord
  belongs_to :idea
  has_many :contacts, -> { order(occurred_at: :desc) },
           class_name: "LicensorContact", dependent: :destroy

  enum :stage, {
    identified: 0,
    contacted: 1,
    meeting: 2,
    negotiating: 3,
    closed_won: 4,
    closed_lost: 5
  }

  validates :company, presence: true
  validates :stage, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_blank: true

  before_create :set_position

  scope :ordered, -> { order(Arel.sql("COALESCE(position, 999999)"), :created_at) }
  scope :open, -> { where.not(stage: [:closed_won, :closed_lost]) }

  # Stage order matches the enum; drives kanban column order and progress.
  STAGE_ORDER = %w[identified contacted meeting negotiating closed_won closed_lost].freeze

  STAGE_LABELS = {
    "identified"  => "Identified",
    "contacted"   => "Contacted",
    "meeting"     => "Meeting",
    "negotiating" => "Negotiating",
    "closed_won"  => "Closed — Won",
    "closed_lost" => "Closed — Lost"
  }.freeze

  # Accent hue per stage (drives pill + column color via --stage-hue).
  STAGE_HUES = {
    "identified"  => 220,
    "contacted"   => 265,
    "meeting"     => 190,
    "negotiating" => 40,
    "closed_won"  => 145,
    "closed_lost" => 8
  }.freeze

  def self.stage_label(stage)
    STAGE_LABELS[stage.to_s] || stage.to_s.humanize
  end

  def self.stage_hue(stage)
    STAGE_HUES.fetch(stage.to_s, 220)
  end

  def stage_label
    self.class.stage_label(stage)
  end

  def stage_hue
    self.class.stage_hue(stage)
  end

  def closed?
    closed_won? || closed_lost?
  end

  # Recompute last_contacted_at from the contact log. Called by LicensorContact.
  def refresh_last_contacted!
    update_column(:last_contacted_at, contacts.maximum(:occurred_at))
  end

  private

  def set_position
    return if position.present?
    max_pos = idea.licensors.where(stage: stage).maximum(:position) || 0
    self.position = max_pos + 1
  end
end
