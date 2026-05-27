class User < ApplicationRecord
  has_many :lists, dependent: :destroy
  has_many :kanban_boards, dependent: :destroy
  has_many :ideas, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :export_jobs, dependent: :destroy
  has_many :topologies, dependent: :destroy
  has_many :build_items, dependent: :destroy
  has_many :submissions, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :facts, dependent: :destroy
  has_many :maxims, dependent: :destroy
  has_many :agent_runs, dependent: :destroy
  has_many :agent_events, dependent: :destroy
  has_many :agent_recommendations, dependent: :destroy

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
    'lock_after_seconds' => 5.minutes.to_i,
    'failed_unlock_cooldown_seconds' => 5.minutes.to_i
  }.freeze
  DEFAULT_AUTHENTICATOR_APP_SETTINGS = {
    'enabled' => false
  }.freeze
  DEFAULT_VOICE_ID_SETTINGS = {
    'enabled' => false
  }.freeze
  DEFAULT_IDEA_WORK_TOKEN_SETTINGS = {
    'enabled' => false
  }.freeze
  DEFAULT_LOCAL_AGENT_SETTINGS = {
    'enabled' => false,
    'destructive_actions_enabled' => false,
    'sleep_seconds' => 30,
    'max_actions_per_cycle' => 20
  }.freeze
  ALLOWED_LOCAL_AGENT_SETTING_KEYS = DEFAULT_LOCAL_AGENT_SETTINGS.keys.freeze
  DEFAULT_GITHUB_SETTINGS = {
    'api_base_url' => 'https://api.github.com'
  }.freeze
  MIN_TYPING_LOCK_SECONDS = 1.minute.to_i
  MAX_TYPING_LOCK_SECONDS = 24.hours.to_i
  MIN_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS = 1.minute.to_i
  MAX_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS = 24.hours.to_i

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

  DEFAULT_DISPLAY_QUOTE_SETTINGS = {
    'text' => ''
  }.freeze


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

  def default_kanban_board
    kanban_boards.ordered.first || kanban_boards.create!(name: "Main Board")
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

  def typing_lock_failed_unlock_cooldown_seconds
    raw_seconds = typing_lock_settings['failed_unlock_cooldown_seconds']
    raw_seconds = typing_lock_settings['failed_unlock_cooldown_minutes'].to_f.minutes.to_i if raw_seconds.blank?
    raw_seconds.to_i.clamp(MIN_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS, MAX_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS)
  end

  def typing_lock_failed_unlock_cooldown_minutes
    typing_lock_failed_unlock_cooldown_seconds / 60
  end

  def typing_fingerprint
    secure_settings_value(typing_lock_settings, 'fingerprint')
  end

  def typing_fingerprint_configured?
    typing_fingerprint.present?
  end

  def active_typing_lock_failed_unlock
    failed_unlock = typing_lock_failed_unlock
    return unless failed_unlock.present?

    cooldown_until = typing_lock_failed_unlock_cooldown_until(failed_unlock)
    return unless cooldown_until&.future?

    failed_unlock
  end

  def typing_lock_failed_unlock
    typing_lock_settings['last_failed_unlock']
  end

  def typing_lock_failed_unlock_cooldown_until(failed_unlock = typing_lock_failed_unlock)
    Time.zone.parse(failed_unlock&.dig('cooldown_until').to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def record_typing_lock_failed_unlock!(match:, challenge_id:)
    failed_unlock = {
      "score" => match.score.to_f,
      "sample_count" => match.sample_count.to_i,
      "compared_features" => match.compared_features.to_i,
      "challenge_id" => challenge_id.to_s,
      "created_at" => Time.current.iso8601,
      "cooldown_until" => typing_lock_failed_unlock_cooldown_seconds.seconds.from_now.iso8601
    }

    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock']['last_failed_unlock'] = failed_unlock
    save!

    failed_unlock
  end

  def clear_typing_lock_failed_unlock!
    return true unless settings&.dig('typing_lock', 'last_failed_unlock')

    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock'].delete('last_failed_unlock')
    save!
  end

  def update_typing_lock_settings(params)
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    lock_after_minutes = params['lock_after_minutes'].presence || typing_lock_timeout_minutes
    lock_after_seconds = (lock_after_minutes.to_f * 60).round.clamp(MIN_TYPING_LOCK_SECONDS, MAX_TYPING_LOCK_SECONDS)
    failed_unlock_cooldown_minutes = params['failed_unlock_cooldown_minutes'].presence || typing_lock_failed_unlock_cooldown_minutes
    failed_unlock_cooldown_seconds = (failed_unlock_cooldown_minutes.to_f * 60).round.clamp(
      MIN_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS,
      MAX_TYPING_LOCK_FAILED_UNLOCK_COOLDOWN_SECONDS
    )

    enabled = ActiveModel::Type::Boolean.new.cast(params.fetch('enabled', false)) == true
    self.settings['typing_lock']['enabled'] = enabled
    self.settings['typing_lock']['lock_after_seconds'] = lock_after_seconds
    self.settings['typing_lock']['failed_unlock_cooldown_seconds'] = failed_unlock_cooldown_seconds
    self.settings['typing_lock'].delete('last_failed_unlock') unless enabled
    save
  end

  def store_typing_fingerprint!(fingerprint)
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock']['enabled'] = true
    self.settings['typing_lock']['fingerprint_ciphertext'] = SecureSettingsPayload.encrypt(fingerprint)
    self.settings['typing_lock'].delete('fingerprint')
    self.settings['typing_lock'].delete('last_failed_unlock')
    save
  end

  def clear_typing_fingerprint!
    self.settings ||= {}
    self.settings['typing_lock'] ||= {}
    self.settings['typing_lock'].delete('fingerprint')
    self.settings['typing_lock'].delete('fingerprint_ciphertext')
    self.settings['typing_lock'].delete('last_failed_unlock')
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
    secure_settings_value(authenticator_app_settings, 'secret').presence
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
      self.settings['authenticator_app']['secret_ciphertext'] = SecureSettingsPayload.encrypt(authenticator_app_secret || AuthenticatorApp.generate_secret)
      self.settings['authenticator_app'].delete('secret')
    else
      self.settings['authenticator_app'] = { 'enabled' => false }
    end

    save
  end

  def voice_id_settings
    DEFAULT_VOICE_ID_SETTINGS.merge(settings&.dig('voice_id') || {})
  end

  def voice_id_enabled?
    ActiveModel::Type::Boolean.new.cast(voice_id_settings['enabled']) == true && voice_id_configured?
  end

  def voice_id_requested?
    ActiveModel::Type::Boolean.new.cast(voice_id_settings['enabled']) == true
  end

  def voice_id_fingerprint
    secure_settings_value(voice_id_settings, 'fingerprint')
  end

  def voice_id_configured?
    voice_id_fingerprint.present? && voice_id_fingerprint['sample_count'].to_i >= VoiceFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT
  end

  def update_voice_id_settings(params)
    enabled = ActiveModel::Type::Boolean.new.cast(params.fetch('enabled', false)) == true
    self.settings ||= {}
    self.settings['voice_id'] ||= {}

    if enabled
      self.settings['voice_id']['enabled'] = true
    else
      self.settings['voice_id'] = { 'enabled' => false }
    end

    save
  end

  def store_voice_id_fingerprint!(fingerprint)
    self.settings ||= {}
    self.settings['voice_id'] ||= {}
    self.settings['voice_id']['enabled'] = true
    self.settings['voice_id']['fingerprint_ciphertext'] = SecureSettingsPayload.encrypt(fingerprint.except('raw_audio', 'audio', 'blob', 'recording'))
    self.settings['voice_id'].delete('fingerprint')
    save
  end

  def clear_voice_id_fingerprint!
    self.settings ||= {}
    self.settings['voice_id'] ||= {}
    self.settings['voice_id'].delete('fingerprint')
    self.settings['voice_id'].delete('fingerprint_ciphertext')
    save
  end

  def security_lock_enabled?
    typing_lock_enabled? || authenticator_app_enabled? || voice_id_requested?
  end

  def security_lock_timeout_seconds
    typing_lock_timeout_seconds
  end

  def idea_draft_unlock_seed
    Rails.application.key_generator.generate_key("idea-draft:user:#{id}:#{created_at.to_i}", 32).unpack1("H*")
  end

  def idea_work_token_settings
    DEFAULT_IDEA_WORK_TOKEN_SETTINGS.merge(settings&.dig('idea_work_tokens') || {})
  end

  def idea_work_tokens_enabled?
    ActiveModel::Type::Boolean.new.cast(idea_work_token_settings['enabled']) == true
  end

  def update_idea_work_token_settings(params)
    enabled = ActiveModel::Type::Boolean.new.cast(params.fetch('enabled', false)) == true
    self.settings ||= {}
    self.settings['idea_work_tokens'] = { 'enabled' => enabled }
    save
  end

  def local_agent_settings
    stored = (settings&.dig('local_agent') || {}).slice(*ALLOWED_LOCAL_AGENT_SETTING_KEYS)
    resolved = DEFAULT_LOCAL_AGENT_SETTINGS.merge(stored.slice(*DEFAULT_LOCAL_AGENT_SETTINGS.keys))

    boolean = ActiveModel::Type::Boolean.new
    resolved['enabled'] = boolean.cast(resolved['enabled']) == true
    resolved['destructive_actions_enabled'] = boolean.cast(resolved['destructive_actions_enabled']) == true
    resolved['sleep_seconds'] = positive_integer_or_default(resolved['sleep_seconds'], DEFAULT_LOCAL_AGENT_SETTINGS['sleep_seconds'])
    resolved['max_actions_per_cycle'] = positive_integer_or_default(
      resolved['max_actions_per_cycle'],
      DEFAULT_LOCAL_AGENT_SETTINGS['max_actions_per_cycle']
    )

    resolved
  end

  def local_agent_enabled?
    local_agent_settings['enabled'] == true
  end

  def local_agent_destructive_actions_enabled?
    local_agent_settings['destructive_actions_enabled'] == true
  end

  def update_local_agent_settings(params)
    values = params.to_h.stringify_keys
    cleaned = {
      'enabled' => ActiveModel::Type::Boolean.new.cast(values.fetch('enabled', false)) == true,
      'destructive_actions_enabled' => ActiveModel::Type::Boolean.new.cast(values.fetch('destructive_actions_enabled', false)) == true,
      'sleep_seconds' => positive_integer_or_default(values['sleep_seconds'], DEFAULT_LOCAL_AGENT_SETTINGS['sleep_seconds']),
      'max_actions_per_cycle' => positive_integer_or_default(values['max_actions_per_cycle'], DEFAULT_LOCAL_AGENT_SETTINGS['max_actions_per_cycle'])
    }

    self.settings ||= {}
    self.settings['local_agent'] = cleaned
    save
  end

  def local_agent_status
    return 'disabled' unless local_agent_enabled?

    latest = agent_runs.recent.first
    return 'stopped' unless latest
    return 'stale' if latest.heartbeat_stale?

    latest.status
  end

  def local_agent_question_threads(limit: 10)
    questions = agent_events.where(event_type: "question").recent.limit(limit).to_a
    answers_by_question_id =
      agent_events
        .where(event_type: "answer", target_type: "AgentEvent", target_id: questions.map(&:id))
        .recent
        .group_by(&:target_id)

    questions.map do |question|
      {
        question: question,
        answer: answers_by_question_id[question.id]&.first
      }
    end
  end

  def github_settings
    stored = settings&.dig('github') || {}
    DEFAULT_GITHUB_SETTINGS.merge(stored.slice('api_base_url')).merge(
      'token_configured' => github_configured?
    )
  end

  def github_token
    secure_settings_value(settings&.dig('github') || {}, 'token').presence
  end

  def github_configured?
    github_token.present?
  end

  def update_github_settings(params)
    values = params.to_h.stringify_keys
    self.settings ||= {}
    self.settings['github'] ||= {}

    if ActiveModel::Type::Boolean.new.cast(values['clear_token']) == true
      self.settings['github'].delete('token')
      self.settings['github'].delete('token_ciphertext')
    elsif values['token'].present?
      self.settings['github']['token_ciphertext'] = SecureSettingsPayload.encrypt(values['token'].to_s.strip)
      self.settings['github'].delete('token')
    end

    api_base_url = values['api_base_url'].presence || settings['github']['api_base_url'].presence || DEFAULT_GITHUB_SETTINGS['api_base_url']
    self.settings['github']['api_base_url'] = api_base_url
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

  def display_quote_settings
    DEFAULT_DISPLAY_QUOTE_SETTINGS.merge(settings&.dig('display_quote') || {})
  end

  def display_quote
    display_quote_settings['text'].to_s
  end

  def display_contrast
    val = settings&.dig('display_contrast').to_s
    return 130 if val == 'high'
    return 100 if val == 'normal' || val.empty?
    int = val.to_i
    int.between?(70, 150) ? int : 100
  end

  def update_display_quote(params)
    h = params.to_h
    quote = h.fetch('quote', '').to_s.strip
    contrast = h.fetch('contrast', '100').to_s.strip
    self.settings ||= {}

    if quote.present?
      self.settings['display_quote'] = { 'text' => quote }
    else
      self.settings.delete('display_quote')
    end

    contrast_int = contrast.to_i.clamp(70, 150)
    if contrast_int == 100
      self.settings.delete('display_contrast')
    else
      self.settings['display_contrast'] = contrast_int.to_s
    end

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

  private

  def positive_integer_or_default(value, default)
    integer = value.to_i
    integer.positive? ? integer : default
  end

  def secure_settings_value(settings_hash, key)
    ciphertext = settings_hash["#{key}_ciphertext"]
    return SecureSettingsPayload.decrypt(ciphertext) if ciphertext.present?

    settings_hash[key]
  end
end
