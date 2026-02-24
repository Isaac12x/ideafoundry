class Idea < ApplicationRecord
  include Notifiable

  belongs_to :user
  belongs_to :template, optional: true
  has_many :idea_topologies, dependent: :destroy
  has_many :topologies, through: :idea_topologies
  has_many :idea_lists, dependent: :destroy
  has_many :lists, through: :idea_lists
  has_many :versions, dependent: :destroy
  has_one_attached :hero_image
  has_many_attached :attachments
  has_rich_text :description

  # Lifecycle management
  enum :state, {
    idea_new: 0, 
    triage: 1, 
    first_try: 2, 
    second_try: 3,
    incubating: 4, 
    validated: 5, 
    parked: 6, 
    rejected: 7, 
    shipped: 8
  }

  # JSON serialization
  serialize :metadata, coder: JSON

  # Validations
  validates :title, presence: true
  validates :state, presence: true
  validates :trl, :difficulty, :opportunity, :timing,
            inclusion: { in: 0..10 }, allow_nil: true
  validates :attempt_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :template_required_fields_present

  # Callbacks
  before_validation :set_defaults, on: :create
  before_save :calculate_score
  after_commit :broadcast_graph_updated, on: :update, if: :title_previously_changed?

  # Scopes
  scope :active, -> { where.not(state: [:rejected, :shipped]) }
  scope :by_state, ->(state) { where(state: state) }
  scope :by_score_range, ->(min, max) { where(computed_score: min..max) }
  scope :in_cool_off, -> { where('cool_off_until > ?', Time.current) }
  scope :cool_off_expired, -> { where('cool_off_until IS NOT NULL AND cool_off_until <= ?', Time.current) }

  # State transition methods
  def transition_to_first_try!
    return false unless can_transition_to_first_try?

    transaction do
      self.state = :first_try
      self.attempt_count += 1
      save!
      create_version("Transitioned to First Try")
    end
  end

  def transition_to_second_try!
    return false unless can_transition_to_second_try?

    transaction do
      self.state = :second_try
      self.attempt_count += 1
      save!
      create_version("Transitioned to Second Try")
    end
  end

  def fail_attempt!(cool_off_duration = 7.days)
    return false unless in_attempt_state?

    transaction do
      self.state = :incubating
      self.cool_off_until = Time.current + cool_off_duration
      save!
      create_version("Attempt failed, entering cool-off")

      # Schedule job to transition back when cool-off expires
      CoolOffTransitionJob.set(wait: cool_off_duration).perform_later(self)
    end
  end

  def complete_attempt!
    return false unless in_attempt_state?

    transaction do
      self.state = :validated
      self.cool_off_until = nil
      save!
      create_version("Attempt completed, validated")
    end
  end

  def park!
    return false if rejected? || shipped?

    transaction do
      self.state = :parked
      self.cool_off_until = nil
      save!
      create_version("Parked")
    end
  end

  def reject!
    return false if shipped?

    transaction do
      self.state = :rejected
      self.cool_off_until = nil
      save!
      create_version("Rejected")
    end
  end

  def ship!
    return false unless validated?

    transaction do
      self.state = :shipped
      self.cool_off_until = nil
      save!
      create_version("Shipped")
    end
  end

  def reopen_from_cool_off!
    return false unless cool_off_expired?

    transaction do
      # Determine next state based on attempt count
      next_state = case attempt_count
      when 1
        :triage  # After first attempt failure, go back to triage
      when 2
        :triage  # After second attempt failure, go back to triage
      else
        :triage  # Default to triage for any other case
      end

      self.state = next_state
      self.cool_off_until = nil
      save!
      create_version("Reopened from cool-off")
    end
  end

  # State checking methods
  def can_transition_to_first_try?
    idea_new? || triage?
  end

  def can_transition_to_second_try?
    (triage? && attempt_count >= 1) || (incubating? && attempt_count >= 1 && !in_cool_off?)
  end

  def in_attempt_state?
    first_try? || second_try?
  end

  def in_cool_off?
    cool_off_until.present? && cool_off_until > Time.current
  end

  def cool_off_expired?
    cool_off_until.present? && cool_off_until <= Time.current
  end

  def can_edit?
    !in_cool_off? || incubating?  # Can only edit notes during cool-off in incubating state
  end

  def can_edit_content?
    !in_cool_off?
  end

  # Cool-off duration helpers
  def remaining_cool_off_time
    return 0 unless in_cool_off?
    (cool_off_until - Time.current).to_i
  end

  def cool_off_duration_in_words
    return nil unless in_cool_off?
    distance_of_time_in_words(Time.current, cool_off_until)
  end

  # Version control methods
  def create_version(commit_message)
    versions.create_from_idea(self, commit_message)
  end

  def latest_version
    versions.order(created_at: :desc).first
  end

  def version_history
    versions.chronological
  end

  def restore_version(version)
    raise ArgumentError, "Version does not belong to this idea" unless version.idea_id == id
    version.restore_to_idea!
  end

  # Scoring history methods
  def scoring_history(limit: 10)
    versions.order(created_at: :desc)
           .limit(limit)
           .select { |v| v.snapshot_data && v.snapshot_data['computed_score'] }
           .map do |version|
      {
        version: version,
        score: version.snapshot_data['computed_score'],
        trl: version.snapshot_data['trl'],
        difficulty: version.snapshot_data['difficulty'],
        opportunity: version.snapshot_data['opportunity'],
        timing: version.snapshot_data['timing'],
        created_at: version.created_at,
        commit_message: version.commit_message
      }
    end
  end

  def score_trend
    history = scoring_history(limit: 5).reverse
    return 'stable' if history.length < 2
    
    recent_scores = history.last(3).map { |h| h[:score].to_f }
    return 'stable' if recent_scores.uniq.length == 1
    
    if recent_scores.last > recent_scores.first
      'improving'
    else
      'declining'
    end
  end

  def score_change_since_last_version
    history = scoring_history(limit: 2)
    return 0 if history.length < 2
    
    current_score = history.first[:score].to_f
    previous_score = history.second[:score].to_f
    current_score - previous_score
  end

  # Template methods
  def apply_template(template)
    return false unless template.user == user
    
    self.template = template
    template.apply_to_idea(self)
  end

  def apply_default_template
    default_template = user.templates.default_for_user(user).first
    apply_template(default_template) if default_template
  end

  def get_custom_field(field_name)
    metadata&.dig(field_name.to_s)
  end

  def set_custom_field(field_name, value)
    self.metadata ||= {}
    self.metadata[field_name.to_s] = value
  end

  def template_sections
    template&.get_sections || default_sections
  end

  def validate_against_template
    return [] unless template
    template.validate_idea_against_template(self)
  end

  # SHA3 integrity hashing (email-ingested ideas only)
  def compute_integrity_hash!
    sha3_key = Rails.application.credentials.dig(:email_ingestion, :sha3_key)
    return unless sha3_key.present?

    digest = SHA3::Digest.new(:sha3_256)
    digest.update(sha3_key)
    digest.update(title.to_s)
    digest.update(description.to_plain_text.to_s)
    attachments.each do |attachment|
      digest.update(attachment.download)
    end

    update_column(:integrity_hash, digest.hexdigest)
  end

  def verify_integrity!
    sha3_key = Rails.application.credentials.dig(:email_ingestion, :sha3_key)
    raise "No SHA3 key configured" unless sha3_key.present?
    raise "No integrity hash stored" unless integrity_hash.present?

    digest = SHA3::Digest.new(:sha3_256)
    digest.update(sha3_key)
    digest.update(title.to_s)
    digest.update(description.to_plain_text.to_s)
    attachments.each do |attachment|
      digest.update(attachment.download)
    end

    digest.hexdigest == integrity_hash
  end

  private

  def broadcast_graph_updated
    ActionCable.server.broadcast("topology_graph:#{user_id}", {
      action: 'node_updated',
      node: { id: "i_#{id}", name: title }
    })
  end

  def set_defaults
    self.state ||= :idea_new
    self.attempt_count ||= 0
    self.trl ||= 0
    self.difficulty ||= 0
    self.opportunity ||= 0
    self.timing ||= 0
  end

  def calculate_score
    return unless trl && difficulty && opportunity && timing
    
    # Use user's configurable scoring weights
    weights = user.scoring_weights
    self.computed_score = (
      trl * weights['trl'].to_f +
      difficulty * weights['difficulty'].to_f +
      opportunity * weights['opportunity'].to_f +
      timing * weights['timing'].to_f
    ).round(2)
  end

  def template_required_fields_present
    return unless template
    
    validation_errors = validate_against_template
    validation_errors.each do |error|
      errors.add(:base, error)
    end
  end

  def default_sections
    %w[header stats description media metadata timeline]
  end
end
