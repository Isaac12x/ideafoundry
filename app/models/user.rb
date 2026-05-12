class User < ApplicationRecord
  has_many :lists, dependent: :destroy
  has_many :ideas, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :export_jobs, dependent: :destroy
  has_many :topologies, dependent: :destroy
  has_many :build_items, dependent: :destroy
  has_many :submissions, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :facts, dependent: :destroy

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

  DEFAULT_TYPING_LOCK_SETTINGS = {
    'enabled' => false,
    'lock_after_seconds' => 5.minutes.to_i
  }.freeze
  DEFAULT_AUTHENTICATOR_APP_SETTINGS = {
    'enabled' => false
  }.freeze
  MIN_TYPING_LOCK_SECONDS = 1.minute.to_i
  MAX_TYPING_LOCK_SECONDS = 24.hours.to_i

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

  DEFAULT_LIST_SETTINGS = {
    'default_view' => 'kanban'
  }.freeze

  ALLOWED_LIST_DEFAULT_VIEWS = %w[kanban named].freeze
  ALLOWED_LIST_SETTING_KEYS = DEFAULT_LIST_SETTINGS.keys.freeze

  ALLOWED_TOPOLOGY_OVERRIDE_KEYS = %w[
    dag_mode show_ideas node_size_topology node_size_idea
    bloom_strength fog_density auto_fit_on_load click_behavior
  ].freeze

  # Tabs that can be toggled on the idea detail page.
  # Description is always visible and not listed here.
  # Entry-kind tabs (tool/competitor/potential_competitor) match IdeaEntry enum kinds.
  AVAILABLE_IDEA_TABS = %w[
    scores media metadata notes todo history drawing
    tool competitor potential_competitor
  ].freeze

  DEFAULT_IDEA_TAB_SETTINGS = {
    'scores' => true,
    'media' => true,
    'metadata' => true,
    'notes' => true,
    'todo' => true,
    'history' => true,
    'drawing' => true,
    'tool' => false,
    'competitor' => false,
    'potential_competitor' => false
  }.freeze

  IDEA_TAB_LABELS = {
    'scores' => 'Scores',
    'media' => 'Media',
    'metadata' => 'Metadata',
    'notes' => 'Notes',
    'todo' => 'Todo',
    'history' => 'History',
    'drawing' => 'Drawings',
    'tool' => 'Tools',
    'competitor' => 'Competitors',
    'potential_competitor' => 'Potential Competitors'
  }.freeze

  IDEA_ENTRY_TABS = %w[tool competitor potential_competitor].freeze

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

  def email_configured?
    email_recipients.present?
  end

  def update_scoring_weights(weights)
    self.settings ||= {}
    self.settings['scoring_weights'] = weights.slice('trl', 'difficulty', 'opportunity', 'timing')
    save!
  end

  def scoring_formula_display
    weights = scoring_weights
    "normalize(TRL × #{weights['trl']} + Opportunity × #{weights['opportunity']} + Timing × #{weights['timing']} + Difficulty × #{weights['difficulty']}) → 0–10"
  end

  def backup_settings
    settings&.dig('backup') || DEFAULT_BACKUP_SETTINGS
  end

  def update_backup_settings(params)
    self.settings ||= {}
    self.settings['backup'] = params.to_h
    save
  end

  def typing_lock_settings
    DEFAULT_TYPING_LOCK_SETTINGS.merge(settings&.dig('typing_lock') || {})
  end

  def typing_lock_enabled?
    ActiveModel::Type::Boolean.new.cast(typing_lock_settings['enabled']) == true
  end

  def typing_lock_timeout_seconds
    raw_seconds = typing_lock_settings['lock_after_seconds']
    raw_seconds = typing_lock_settings['lock_after_minutes'].to_f.minutes.to_i if raw_seconds.blank?
    raw_seconds.to_i.clamp(MIN_TYPING_LOCK_SECONDS, MAX_TYPING_LOCK_SECONDS)
  end

  def typing_lock_timeout_minutes
    typing_lock_timeout_seconds / 60
  end

  def typing_fingerprint
    typing_lock_settings['fingerprint']
  end

  def typing_fingerprint_configured?
    typing_fingerprint.present?
  end

  def update_typing_lock_settings(params)
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    lock_after_minutes = params['lock_after_minutes'].presence || typing_lock_timeout_minutes
    lock_after_seconds = (lock_after_minutes.to_f * 60).round.clamp(MIN_TYPING_LOCK_SECONDS, MAX_TYPING_LOCK_SECONDS)

    self.settings['typing_lock']['enabled'] = ActiveModel::Type::Boolean.new.cast(params.fetch('enabled', false)) == true
    self.settings['typing_lock']['lock_after_seconds'] = lock_after_seconds
    save
  end

  def store_typing_fingerprint!(fingerprint)
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock']['enabled'] = true
    self.settings['typing_lock']['fingerprint'] = fingerprint
    save
  end

  def clear_typing_fingerprint!
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock'].delete('fingerprint')
    save
  end

  def authenticator_app_settings
    DEFAULT_AUTHENTICATOR_APP_SETTINGS.merge(settings&.dig('authenticator_app') || {})
  end

  def authenticator_app_enabled?
    ActiveModel::Type::Boolean.new.cast(authenticator_app_settings['enabled']) == true && authenticator_app_configured?
  end

  def authenticator_app_configured?
    authenticator_app_secret.present?
  end

  def authenticator_app_secret
    authenticator_app_settings['secret'].presence
  end

  def authenticator_app_provisioning_uri
    return unless authenticator_app_secret

    AuthenticatorApp.provisioning_uri(secret: authenticator_app_secret, account: email)
  end

  def update_authenticator_app_settings(params)
    enabled = ActiveModel::Type::Boolean.new.cast(params.fetch('enabled', false)) == true
    self.settings ||= {}
    self.settings['authenticator_app'] ||= {}

    if enabled
      self.settings['authenticator_app']['enabled'] = true
      self.settings['authenticator_app']['secret'] = authenticator_app_secret || AuthenticatorApp.generate_secret
    else
      self.settings['authenticator_app'] = { 'enabled' => false }
    end

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

  def list_settings
    stored = settings&.dig('list_settings') || {}
    DEFAULT_LIST_SETTINGS.merge(stored).tap do |resolved|
      resolved['default_view'] = DEFAULT_LIST_SETTINGS['default_view'] unless ALLOWED_LIST_DEFAULT_VIEWS.include?(resolved['default_view'])
    end
  end

  def update_list_settings(params)
    cleaned = params.to_h.slice(*ALLOWED_LIST_SETTING_KEYS)
    cleaned['default_view'] = DEFAULT_LIST_SETTINGS['default_view'] unless ALLOWED_LIST_DEFAULT_VIEWS.include?(cleaned['default_view'])
    self.settings ||= {}
    self.settings['list_settings'] = cleaned
    save
  end

  def idea_tab_settings
    stored = (settings&.dig('idea_tabs') || {}).slice(*AVAILABLE_IDEA_TABS)
    # Drop nil values so DEFAULTS apply for keys that were never explicitly set
    # (pre-fix checkbox submissions stored unchecked tabs as nil).
    stored.reject! { |_, v| v.nil? }
    DEFAULT_IDEA_TAB_SETTINGS.merge(stored)
  end

  def idea_tab_enabled?(tab_name)
    key = tab_name.to_s
    return false unless AVAILABLE_IDEA_TABS.include?(key)
    idea_tab_settings[key] == true
  end

  def enabled_idea_tabs
    idea_tab_settings.select { |_, v| v }.keys
  end

  def kb_folders
    Array(settings&.dig('kb', 'folders'))
  end

  def update_kb_folders(paths)
    self.settings ||= {}
    self.settings['kb'] ||= {}
    self.settings['kb']['folders'] = Array(paths).map(&:strip).reject(&:blank?)
    save
  end

  def update_idea_tab_settings(params)
    # Unchecked checkboxes are absent from params — coerce to a strict boolean
    # (not nil) so reads don't fall back to defaults and silently re-enable them.
    cleaned = AVAILABLE_IDEA_TABS.each_with_object({}) do |key, acc|
      acc[key] = ActiveModel::Type::Boolean.new.cast(params[key]) == true
    end
    self.settings ||= {}
    self.settings['idea_tabs'] = cleaned
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
