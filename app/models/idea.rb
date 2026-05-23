class Idea < ApplicationRecord
  include Notifiable

  belongs_to :user
  belongs_to :template, optional: true
  has_many :idea_topologies, dependent: :destroy
  has_many :topologies, through: :idea_topologies,
                         after_add: :track_github_repository_after_topology_change,
                         after_remove: :track_github_repository_after_topology_change
  has_many :idea_lists, dependent: :destroy
  has_many :lists, through: :idea_lists
  has_many :versions, -> { order(created_at: :desc) }, dependent: :destroy
  has_many :idea_agent_tokens, dependent: :destroy
  has_many :todo_items, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :idea_entries, dependent: :destroy
  has_many :drawings, dependent: :destroy
  has_one :github_repository, dependent: :destroy
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
  # napkin_calculations is a native json column (auto-serialized by Rails)

  # Validations
  validates :title, presence: true, unless: :draft?
  validates :state, presence: true
  validates :trl, :difficulty, :opportunity, :timing,
            inclusion: { in: 0..10 }, allow_nil: true
  validates :attempt_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :template_required_fields_present
  validate :napkin_calculations_within_limits

  # Callbacks
  before_validation :set_defaults, on: :create
  before_save :calculate_score
  before_destroy :destroy_versions_in_dependency_order
  around_destroy :suppress_history_tracking_during_destroy
  after_update_commit :record_automatic_history_version, if: :automatic_history_version_needed?
  after_commit :broadcast_graph_updated, on: :update, if: :title_previously_changed?
  after_commit :track_github_repository_later, on: [:create, :update], unless: :draft?

  # Scopes
  scope :active, -> { where.not(state: [:rejected, :shipped]).where(discarded_at: nil, draft: false) }
  scope :non_draft, -> { where(draft: false) }
  scope :drafts, -> { where(draft: true) }
  scope :stale_drafts, ->(older_than = 24.hours.ago) { drafts.where("ideas.updated_at < ?", older_than) }
  scope :by_state, ->(state) { where(state: state) }
  scope :by_score_range, ->(min, max) { where(computed_score: min..max) }
  scope :in_cool_off, -> { where('cool_off_until > ?', Time.current) }
  scope :cool_off_expired, -> { where('cool_off_until IS NOT NULL AND cool_off_until <= ?', Time.current) }
  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }
  scope :with_discarded, -> { unscope(:where).where.not(discarded_at: nil) }

  def hero_drawing
    drawings.hero.first
  end

  def attachment_drawings
    drawings.attachment.ordered
  end

  def general_drawings
    drawings.general.ordered
  end

  def ordered_attachments
    attachments.attachments.order(Arel.sql("COALESCE(position, 2147483647) ASC"), :created_at)
  end

  def ocr_attachment_parts
    ordered_attachments.each_with_object([]) do |attachment, parts|
      next unless attachment.ocr_complete?

      attachment.ocr_parts.each do |part|
        parts << { attachment: attachment, text: part }
      end
    end
  end

  def enqueue_attachment_ocr!
    ordered_attachments.each do |attachment|
      next unless AttachmentOcrJob.ocr_supported?(attachment)
      next if attachment.ocr_status.in?(["queued", "processing", "complete"])

      attachment.update!(ocr_status: "queued", ocr_error: nil)
      AttachmentOcrJob.perform_later(attachment.id)
    end
  end

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
    record_history!(commit_message)
  end

  def record_history!(commit_message = "Updated idea", parent_version: nil, force: false, replace_message: true, automatic: false)
    return if destroyed? || !persisted?

    Version.create_from_idea(self, commit_message, parent_version, force: force, replace_message: replace_message, automatic: automatic)
  end

  def mark_reusable_history_version!(version)
    @reusable_history_version_id = version&.id
  end

  def reusable_history_version?(version)
    @reusable_history_version_id.present? && version&.id == @reusable_history_version_id
  end

  def clear_reusable_history_version!
    @reusable_history_version_id = nil
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
    effective_field_definitions.select { |field| field['required'] == true }.filter_map do |field|
      key = field['instance_id'] || field['name']
      value = respond_to?(key) ? public_send(key) : metadata&.dig(key)
      "#{field['label'] || field['name'].humanize} is required" if value.blank?
    end
  end

  def effective_field_definitions
    merge_field_definitions(
      template&.field_definitions || [],
      topologies.flat_map(&:effective_default_field_definitions)
    )
  end

  def effective_tab_definitions
    tabs = template&.effective_tab_definitions || [{ 'name' => 'general', 'label' => 'General', 'position' => 0 }]
    existing = tabs.index_by { |tab| tab['name'] }

    effective_field_definitions.each do |field|
      tab_name = field['tab'].presence || tabs.first['name']
      next if existing.key?(tab_name)

      existing[tab_name] = {
        'name' => tab_name,
        'label' => tab_name.humanize,
        'position' => existing.length
      }
    end

    existing.values.sort_by { |tab| tab['position'].to_i }
  end

  def effective_fields_by_tab
    tabs = effective_tab_definitions
    default_tab = tabs.first&.dig('name') || 'general'

    grouped = {}
    tabs.each { |tab| grouped[tab['name']] = [] }

    effective_field_definitions.each do |field|
      tab = field['tab'].presence || default_tab
      grouped[tab] ||= []
      grouped[tab] << field
    end

    grouped.each { |_, fields| fields.sort_by! { |field| field['position'].to_i } }
    grouped
  end

  def effective_field_by_instance_id(instance_id)
    effective_field_definitions.find { |field| field['instance_id'] == instance_id }
  end

  def software_topology?
    topologies.any? { |topology| topology.name.to_s.casecmp("software").zero? }
  end

  def github_repository_url
    values = metadata.is_a?(Hash) ? metadata : {}
    preferred_key = values.keys.find { |key| key.to_s.match?(/\Agithub(_repository)?_url\z/i) }
    return values[preferred_key].to_s.strip if preferred_key && values[preferred_key].present?

    repo_key = values.keys.find { |key| key.to_s.match?(/github|repository|repo/i) && values[key].to_s.include?("github.com") }
    return values[repo_key].to_s.strip if repo_key

    values.values.find { |value| value.to_s.include?("github.com") }.to_s.strip.presence
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

    new_hash = digest.hexdigest
    update_column(:integrity_hash, new_hash)
    record_history!("Updated integrity hash", automatic: true) if integrity_hash == new_hash
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

  # Soft delete / archive
  def archived?
    discarded_at.present?
  end

  def archive!
    update!(discarded_at: Time.current)
  end

  def restore!
    update!(discarded_at: nil)
  end

  # Enrichment helpers
  def enrichment_data
    metadata&.dig("enrichment")
  end

  def enriched?
    enrichment_data.present? &&
      enrichment_data["enriched_at"].present? &&
      Time.parse(enrichment_data["enriched_at"]) > 24.hours.ago
  rescue StandardError
    false
  end

  # Napkin calculations helpers
  def napkin_present?
    napkin_calculations.is_a?(Hash) && napkin_calculations["cells"].is_a?(Hash) && napkin_calculations["cells"].any?
  end

  def napkin_cell(ref)
    return nil unless napkin_calculations.is_a?(Hash)
    napkin_calculations.dig("cells", ref)
  end

  def append_intake_update!(body:, source: nil, intake_reference: nil)
    changed = false

    transaction do
      cleaned_body = body.to_s.strip
      if cleaned_body.present?
        current_body = description.to_plain_text.to_s.strip
        self.description = [current_body.presence, cleaned_body].compact.join("\n\n---\n\n")
        changed = true
      end

      self.metadata ||= {}
      references = Array(metadata["submission_references"]).map(&:to_s)
      if intake_reference.present? && !references.include?(intake_reference)
        metadata["submission_references"] = references << intake_reference
        metadata["submission_reference"] ||= intake_reference
        changed = true
      end

      if source.present? && metadata["last_intake_source"] != source
        metadata["last_intake_source"] = source
        changed = true
      end

      save! if changed
      create_version("Updated via intake #{intake_reference || "chat"}") if changed
    end

    changed
  end

  private

  def self.without_history_tracking
    previous = Thread.current[:idea_history_tracking_suppressed]
    Thread.current[:idea_history_tracking_suppressed] = true
    yield
  ensure
    Thread.current[:idea_history_tracking_suppressed] = previous
  end

  def self.history_tracking_suppressed?
    Thread.current[:idea_history_tracking_suppressed]
  end

  def automatic_history_version_needed?
    return false if draft?
    return false if self.class.history_tracking_suppressed?

    history_relevant_previous_changes.any?
  end

  def record_automatic_history_version
    record_history!(automatic_history_commit_message, replace_message: false, automatic: true)
  end

  def history_relevant_previous_changes
    previous_changes.except("updated_at")
  end

  def automatic_history_commit_message
    changes = history_relevant_previous_changes
    scoring_fields = %w[trl difficulty opportunity timing]
    changed_scores = scoring_fields.select { |field| changes.key?(field) }

    if changes.key?("state")
      "State changed to #{state.humanize}"
    elsif changes.key?("napkin_calculations")
      "Updated calculations"
    elsif changes.key?("metadata")
      "Updated metadata"
    elsif changed_scores.any? && (changes.keys - scoring_fields - %w[computed_score]).empty?
      deltas = changed_scores.map { |field| "#{field}: #{changes[field][0]} -> #{changes[field][1]}" }
      "Score update (#{deltas.join(', ')})"
    elsif changes.key?("title")
      "Updated title and details"
    else
      "Updated idea"
    end
  end

  def suppress_history_tracking_during_destroy
    self.class.without_history_tracking { yield }
  end

  def destroy_versions_in_dependency_order
    versions.reorder(created_at: :desc).to_a.each do |version|
      version.destroy unless version.destroyed?
    end
  end

  def broadcast_graph_updated
    ActionCable.server.broadcast("topology_graph:#{user_id}", {
      action: 'node_updated',
      node: { id: "i_#{id}", name: title }
    })
  end

  def track_github_repository_later
    TrackGithubRepositoryJob.perform_later(id)
  end

  def track_github_repository_after_topology_change(_topology)
    track_github_repository_later if persisted? && !draft?
  end

  def merge_field_definitions(*definition_sets)
    definition_sets.flatten.compact.each_with_object({}) do |field, merged|
      key = field['instance_id'].presence || field['name']
      next if key.blank?

      merged[key] = field
    end.values
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
    w = [weights['trl'].to_f, weights['difficulty'].to_f, weights['opportunity'].to_f, weights['timing'].to_f]

    raw = trl * w[0] + difficulty * w[1] + opportunity * w[2] + timing * w[3]

    # Normalize to 0.0–10.0 range regardless of weight signs
    raw_min = 10.0 * w.select(&:negative?).sum
    raw_max = 10.0 * w.select(&:positive?).sum

    self.computed_score = if raw_max == raw_min
                           0.0
                         else
                           ((raw - raw_min) / (raw_max - raw_min) * 10.0).round(2)
                         end
  end

  def template_required_fields_present
    return if effective_field_definitions.blank?

    validation_errors = validate_against_template
    validation_errors.each do |error|
      errors.add(:base, error)
    end
  end

  def napkin_calculations_within_limits
    return if napkin_calculations.nil?
    unless napkin_calculations.is_a?(Hash)
      errors.add(:napkin_calculations, "must be a hash")
      return
    end

    rows = napkin_calculations["rows"].to_i
    cols = napkin_calculations["cols"].to_i
    cells = napkin_calculations["cells"]

    errors.add(:napkin_calculations, "rows must be 1..100") if rows < 1 || rows > 100
    errors.add(:napkin_calculations, "cols must be 1..26") if cols < 1 || cols > 26

    if cells.is_a?(Hash) && cells.size > 2000
      errors.add(:napkin_calculations, "too many cells (max 2000)")
    end
  end

  def default_sections
    %w[header stats description media metadata timeline]
  end
end
