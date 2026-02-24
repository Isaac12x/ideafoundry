class User < ApplicationRecord
  has_many :lists, dependent: :destroy
  has_many :ideas, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :export_jobs, dependent: :destroy
  has_many :topologies, dependent: :destroy
  has_many :build_items, dependent: :destroy

  # Single-user application - one user per instance
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true

  # Settings stored as JSON
  serialize :settings, coder: JSON

  # Default scoring weights
  DEFAULT_SCORING_WEIGHTS = {
    'trl' => 0.3,
    'difficulty' => -0.1,
    'opportunity' => 0.4,
    'timing' => 0.2
  }.freeze

  DEFAULT_EMAIL_SETTINGS = {
    'recipients' => ''
  }.freeze

  ALLOWED_PRESETS = %w[alert info success neutral digest].freeze

  DEFAULT_BACKUP_SETTINGS = {
    'frequency' => 'never',
    'retention_days' => 30,
    'max_backups' => 5,
    'auto_cleanup' => true,
    'email_notification' => false
  }.freeze

  ALLOWED_NOTIFICATION_TRIGGERS = %w[
    state_changed score_changed added_to_list created
    digest_daily digest_weekly webhook_triggered
  ].freeze

  ALLOWED_NOTIFICATION_MAILERS = {
    'state_changed'      => %w[event_notification share_idea],
    'score_changed'      => %w[event_notification share_idea],
    'added_to_list'      => %w[event_notification share_idea],
    'created'            => %w[event_notification share_idea],
    'webhook_triggered'  => %w[event_notification share_idea],
    'digest_daily'       => %w[digest],
    'digest_weekly'      => %w[digest]
  }.freeze

  DEFAULT_NOTIFICATION_TEMPLATES = {
    'state_changed'      => 'event_notification',
    'score_changed'      => 'event_notification',
    'added_to_list'      => 'event_notification',
    'created'            => 'event_notification',
    'webhook_triggered'  => 'event_notification',
    'digest_daily'       => 'digest',
    'digest_weekly'      => 'digest'
  }.freeze

  DEFAULT_NOTIFICATION_CONTENT = {
    'include_scores' => true,
    'include_description' => true,
    'include_external_content' => true
  }.freeze

  DEFAULT_TOPOLOGY_SETTINGS = {
    'default_dag_mode' => 'td',
    'show_ideas' => true,
    'node_size_topology' => 6,
    'node_size_idea' => 3,
    'bloom_strength' => 0.8,
    'fog_density' => 0.015,
    'auto_fit_on_load' => true,
    'click_behavior' => 'navigate',
    'default_color' => '#DAA520',
    'default_type' => 'custom',
    'max_depth' => 5,
    'default_view' => 'tree',
    'sort_order' => 'position'
  }.freeze

  ALLOWED_TOPOLOGY_SETTING_KEYS = DEFAULT_TOPOLOGY_SETTINGS.keys.freeze

  ALLOWED_TOPOLOGY_OVERRIDE_KEYS = %w[
    dag_mode show_ideas node_size_topology node_size_idea
    bloom_strength fog_density auto_fit_on_load click_behavior
  ].freeze

  def scoring_weights
    settings&.dig('scoring_weights') || DEFAULT_SCORING_WEIGHTS
  end

  def email_settings
    settings&.dig('email') || DEFAULT_EMAIL_SETTINGS
  end

  def update_email_settings(email_params)
    self.settings ||= {}
    self.settings['email'] = email_params.to_h.slice('recipients')
    save
  end

  def event_presets
    settings&.dig('event_presets') || {}
  end

  def event_preset_for(event_type)
    key = event_type.to_s
    chosen = event_presets[key]
    return chosen if ALLOWED_PRESETS.include?(chosen)
    EmailPresetHelper::DEFAULT_EVENT_PRESETS[key] || 'neutral'
  end

  def update_event_presets(hash)
    self.settings ||= {}
    cleaned = hash.to_h.each_with_object({}) do |(event, preset), acc|
      event = event.to_s
      preset = preset.to_s
      next unless ALLOWED_PRESETS.include?(preset)
      acc[event] = preset
    end
    self.settings['event_presets'] = cleaned
    save
  end

  def email_recipients
    email_settings['recipients'].to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def update_scoring_weights(weights)
    self.settings ||= {}
    self.settings['scoring_weights'] = weights.slice('trl', 'difficulty', 'opportunity', 'timing')
    save!
  end

  def scoring_formula_display
    weights = scoring_weights
    "TRL × #{weights['trl']} + Opportunity × #{weights['opportunity']} + Timing × #{weights['timing']} + Difficulty × #{weights['difficulty']}"
  end

  def backup_settings
    settings&.dig('backup') || DEFAULT_BACKUP_SETTINGS
  end

  def update_backup_settings(params)
    self.settings ||= {}
    self.settings['backup'] = params.to_h
    save
  end

  def notification_triggers
    settings&.dig('notification_triggers') || []
  end

  def update_notification_triggers(triggers)
    self.settings ||= {}
    self.settings['notification_triggers'] = Array(triggers).select { |t| ALLOWED_NOTIFICATION_TRIGGERS.include?(t) }
    save
  end

  def notification_enabled?(event)
    notification_triggers.include?(event.to_s)
  end

  def notification_content(event_type = nil)
    base = settings&.dig('notification_content') || {}
    if event_type
      base[event_type.to_s] || DEFAULT_NOTIFICATION_CONTENT
    else
      base
    end
  end

  def update_notification_content(content_settings)
    self.settings ||= {}
    self.settings['notification_content'] = content_settings.to_h
    save
  end

  def notification_templates
    settings&.dig('notification_templates') || {}
  end

  def notification_template_for(event_type)
    key = event_type.to_s
    chosen = notification_templates[key]
    allowed = ALLOWED_NOTIFICATION_MAILERS[key] || %w[event_notification]
    allowed.include?(chosen) ? chosen : DEFAULT_NOTIFICATION_TEMPLATES[key] || 'event_notification'
  end

  def update_notification_templates(hash)
    self.settings ||= {}
    cleaned = hash.to_h.each_with_object({}) do |(trigger, template), acc|
      trigger = trigger.to_s
      template = template.to_s
      allowed = ALLOWED_NOTIFICATION_MAILERS[trigger]
      next unless allowed&.include?(template)
      acc[trigger] = template
    end
    self.settings['notification_templates'] = cleaned
    save
  end

  def topology_settings
    DEFAULT_TOPOLOGY_SETTINGS.merge(settings&.dig('topology_settings') || {})
  end

  def update_topology_settings(params)
    self.settings ||= {}
    self.settings['topology_settings'] = params.to_h.slice(*ALLOWED_TOPOLOGY_SETTING_KEYS)
    save
  end

  def topology_overrides_for(topology_id)
    overrides = settings&.dig('topology_overrides', topology_id.to_s) || {}
    topology_settings.merge(overrides)
  end

  def update_topology_overrides(topology_id, params)
    self.settings ||= {}
    self.settings['topology_overrides'] ||= {}
    filtered = params.to_h.slice(*ALLOWED_TOPOLOGY_OVERRIDE_KEYS)
    if filtered.empty?
      self.settings['topology_overrides'].delete(topology_id.to_s)
    else
      self.settings['topology_overrides'][topology_id.to_s] = filtered
    end
    save
  end
end
