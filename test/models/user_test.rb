require "test_helper"
require "erb"
require "yaml"

class UserTest < ActiveSupport::TestCase
  test "typing lock defaults to disabled with five minute timeout" do
    user = User.new(email: "fresh@example.com", name: "Fresh", settings: nil)

    refute user.typing_lock_enabled?
    assert_equal 300, user.typing_lock_timeout_seconds
    refute user.typing_fingerprint_configured?
  end

  test "typing lock settings can be updated and clamped" do
    user = users(:one)

    assert user.update_typing_lock_settings("enabled" => "0", "lock_after_minutes" => "9999")

    assert_equal false, user.typing_lock_enabled?
    assert_equal 86_400, user.typing_lock_timeout_seconds
  end

  test "double encoded settings are normalized on read" do
    user = users(:one)
    original_settings = user.settings.deep_dup
    encoded_settings = {
      "typing_lock" => {
        "enabled" => false,
        "lock_after_seconds" => 300
      }
    }.to_json

    User.connection.execute(
      "UPDATE users SET settings = #{User.connection.quote(encoded_settings.to_json)} WHERE id = #{user.id}"
    )

    user = User.find(user.id)

    assert_kind_of Hash, user.settings
    refute user.typing_lock_enabled?
  ensure
    users(:one).update!(settings: original_settings) if defined?(original_settings)
  end

  test "production sqlite databases are configured for SQLCipher encryption" do
    raw_config = ERB.new(Rails.root.join("config/database.yml").read).result
    database_config = YAML.safe_load(raw_config, aliases: true)

    assert_equal true, database_config.fetch("production").fetch("primary").fetch("sqlcipher")
    assert_equal true, database_config.fetch("production").fetch("queue").fetch("sqlcipher")
  end

  test "typing fingerprint can be stored encrypted and cleared" do
    user = users(:one)
    fingerprint = { "version" => 1, "keys" => { "a" => { "mean" => 90 } } }

    assert user.store_typing_fingerprint!(fingerprint)
    assert user.typing_fingerprint_configured?
    assert_equal fingerprint, user.typing_fingerprint

    raw_settings = user.reload.settings.fetch("typing_lock")
    assert raw_settings["fingerprint_ciphertext"].present?
    assert_nil raw_settings["fingerprint"]
    refute_includes raw_settings["fingerprint_ciphertext"], "mean"

    assert user.clear_typing_fingerprint!
    refute user.typing_fingerprint_configured?
  end

  test "typing fingerprint reader supports legacy plaintext templates" do
    user = users(:one)
    fingerprint = { "version" => 1, "keys" => { "a" => { "mean" => 90 } } }
    user.update!(settings: { "typing_lock" => { "enabled" => true, "fingerprint" => fingerprint } })

    assert_equal fingerprint, user.typing_fingerprint
    assert user.typing_fingerprint_configured?
  end

  test "authenticator app settings default to disabled" do
    user = User.new(email: "fresh-auth@example.com", name: "Fresh Auth", settings: nil)

    refute user.authenticator_app_enabled?
    refute user.authenticator_app_configured?
    assert_nil user.authenticator_app_secret
  end

  test "authenticator app settings generate and clear a secret" do
    user = users(:one)

    assert user.update_authenticator_app_settings("enabled" => "1")

    assert user.authenticator_app_enabled?
    assert user.authenticator_app_configured?
    assert_match(/\A[A-Z2-7]{32}\z/, user.authenticator_app_secret)
    assert_includes user.authenticator_app_provisioning_uri, "otpauth://totp/Idea%20Foundry:"

    raw_settings = user.reload.settings.fetch("authenticator_app")
    assert raw_settings["secret_ciphertext"].present?
    assert_nil raw_settings["secret"]
    refute_includes raw_settings["secret_ciphertext"], user.authenticator_app_secret

    secret = user.authenticator_app_secret

    assert user.update_authenticator_app_settings("enabled" => "1")
    assert_equal secret, user.authenticator_app_secret

    assert user.update_authenticator_app_settings("enabled" => "0")
    refute user.authenticator_app_enabled?
    refute user.authenticator_app_configured?
    assert_nil user.authenticator_app_secret
  end

  test "mobile uplink settings generate and clear a connection id" do
    user = users(:one)

    assert user.update_mobile_uplink_settings("enabled" => "1")

    assert user.mobile_uplink_enabled?
    assert user.mobile_uplink_configured?
    assert_match(/\A[A-Za-z0-9_-]{24}\z/, user.mobile_uplink_id)
    assert_includes user.mobile_uplink_pairing_payload(workspace_url: "https://ideas.local:8443"), user.mobile_uplink_id
    assert_includes user.mobile_uplink_pairing_payload(workspace_url: "https://ideas.local:8443"), "super-secure"

    connect_id = user.mobile_uplink_id

    assert user.update_mobile_uplink_settings("enabled" => "1")
    assert_equal connect_id, user.mobile_uplink_id

    assert user.update_mobile_uplink_settings("enabled" => "0")
    refute user.reload.mobile_uplink_enabled?
    refute user.mobile_uplink_configured?
    assert_nil user.mobile_uplink_id
  end

  test "voice id stores a derived fingerprint and can be disabled without raw audio" do
    user = users(:one)
    samples = [
      { "transcript" => "By my will and power you will open. Open sesame", "duration_ms" => 1900, "rms" => 0.42 },
      { "transcript" => "By my will and power, you will open. Open sesame!", "duration_ms" => 2050, "rms" => 0.39 },
      { "transcript" => "By my will and power you will open open sesame", "duration_ms" => 1980, "rms" => 0.41 }
    ]

    assert user.store_voice_id_fingerprint!(VoiceFingerprint.build(samples: samples))

    assert user.voice_id_enabled?
    assert user.voice_id_configured?
    assert_equal 3, user.voice_id_fingerprint["sample_count"]
    assert_equal VoiceFingerprint::CANONICAL_PHRASE, user.voice_id_fingerprint["phrase"]
    assert_nil user.voice_id_fingerprint["raw_audio"]

    raw_settings = user.reload.settings.fetch("voice_id")
    assert raw_settings["fingerprint_ciphertext"].present?
    assert_nil raw_settings["fingerprint"]
    refute_includes raw_settings["fingerprint_ciphertext"], VoiceFingerprint::CANONICAL_PHRASE

    assert user.update_voice_id_settings("enabled" => "0")
    refute user.reload.voice_id_enabled?
    refute user.voice_id_configured?
  end

  test "voice id reader supports legacy plaintext templates" do
    user = users(:one)
    fingerprint = VoiceFingerprint.build(samples: [
      { "transcript" => "By my will and power you will open. Open sesame", "duration_ms" => 1900, "rms" => 0.42 },
      { "transcript" => "By my will and power, you will open. Open sesame!", "duration_ms" => 2050, "rms" => 0.39 },
      { "transcript" => "By my will and power you will open open sesame", "duration_ms" => 1980, "rms" => 0.41 }
    ])
    user.update!(settings: { "voice_id" => { "enabled" => true, "fingerprint" => fingerprint } })

    assert user.voice_id_enabled?
    assert_equal fingerprint, user.voice_id_fingerprint
  end

  test "voice id requires the canonical unlock phrase" do
    user = users(:one)
    fingerprint = VoiceFingerprint.build(samples: [
      { "transcript" => "By my will and power you will open. Open sesame", "duration_ms" => 1900, "rms" => 0.42 },
      { "transcript" => "By my will and power, you will open. Open sesame!", "duration_ms" => 2050, "rms" => 0.39 },
      { "transcript" => "By my will and power you will open open sesame", "duration_ms" => 1980, "rms" => 0.41 }
    ])
    user.store_voice_id_fingerprint!(fingerprint)

    assert VoiceFingerprint.match?(template: user.voice_id_fingerprint, transcript: "By my will and power you will open. Open sesame", sample: { "duration_ms" => 2000, "rms" => 0.40 })
    refute VoiceFingerprint.match?(template: user.voice_id_fingerprint, transcript: "please open", sample: { "duration_ms" => 2000, "rms" => 0.40 })
  end

  test "security lock is enabled by any configured lock combination" do
    user = users(:one)
    user.update!(settings: {})
    refute user.security_lock_enabled?

    user.update_authenticator_app_settings("enabled" => "1")
    assert user.security_lock_enabled?

    user.update_authenticator_app_settings("enabled" => "0")
    refute user.security_lock_enabled?

    user.store_voice_id_fingerprint!(VoiceFingerprint.build(samples: [
      { "transcript" => "By my will and power you will open. Open sesame", "duration_ms" => 1900, "rms" => 0.42 },
      { "transcript" => "By my will and power, you will open. Open sesame!", "duration_ms" => 2050, "rms" => 0.39 },
      { "transcript" => "By my will and power you will open open sesame", "duration_ms" => 1980, "rms" => 0.41 }
    ]))
    assert user.security_lock_enabled?
  end

  test "idea work tokens default to disabled" do
    user = User.new(email: "fresh-agent@example.com", name: "Fresh Agent", settings: nil)

    refute user.idea_work_tokens_enabled?
  end

  test "local agent settings default to disabled" do
    user = User.new(email: "fresh-local-agent@example.com", name: "Fresh Local Agent", settings: nil)

    assert_equal User::DEFAULT_LOCAL_AGENT_SETTINGS, user.local_agent_settings
    refute user.local_agent_enabled?
    refute user.local_agent_destructive_actions_enabled?
  end

  test "local agent settings persist only allowed keys" do
    user = users(:one)

    assert user.update_local_agent_settings(
      "enabled" => "1",
      "destructive_actions_enabled" => "0",
      "sleep_seconds" => "12",
      "max_actions_per_cycle" => "7",
      "model" => "  qwen2.5-coder  ",
      "base_url" => "  http://localhost:11434/v1  ",
      "hacker" => "bad"
    )

    settings = user.reload.local_agent_settings
    assert_equal true, settings["enabled"]
    assert_equal false, settings["destructive_actions_enabled"]
    assert_equal 12, settings["sleep_seconds"]
    assert_equal 7, settings["max_actions_per_cycle"]
    refute_includes settings, "model"
    refute_includes settings, "base_url"
    assert_nil user.settings.dig("local_agent", "model")
    assert_nil user.settings.dig("local_agent", "base_url")
    assert_nil user.settings.dig("local_agent", "hacker")
  end

  test "idea work token settings can be toggled" do
    user = users(:one)

    assert user.update_idea_work_token_settings("enabled" => "1", "hacker" => "bad")

    assert user.idea_work_tokens_enabled?
    assert_nil user.reload.settings.dig("idea_work_tokens", "hacker")

    assert user.update_idea_work_token_settings("enabled" => "0")

    refute user.reload.idea_work_tokens_enabled?
  end

  test "github token can be stored encrypted and cleared" do
    user = users(:one)

    assert user.update_github_settings("token" => "ghp_secret_token")

    assert user.github_configured?
    assert_equal "ghp_secret_token", user.github_token

    raw_settings = user.reload.settings.fetch("github")
    assert raw_settings["token_ciphertext"].present?
    assert_nil raw_settings["token"]
    refute_includes raw_settings["token_ciphertext"], "ghp_secret_token"

    assert user.update_github_settings("clear_token" => "1")
    refute user.reload.github_configured?
    assert_nil user.github_token
  end

  def setup
    @user = User.new(email: "test@example.com", name: "Test User")
  end

  test "should be valid with valid attributes" do
    assert @user.valid?
  end

  test "should require email" do
    @user.email = nil
    assert_not @user.valid?
    assert_includes @user.errors[:email], "can't be blank"
  end

  test "should require name" do
    @user.name = nil
    assert_not @user.valid?
    assert_includes @user.errors[:name], "can't be blank"
  end

  test "should require unique email" do
    @user.save!
    duplicate_user = User.new(email: @user.email, name: "Another User")
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "should have many lists" do
    assert_respond_to @user, :lists
  end

  test "should have many ideas through lists" do
    assert_respond_to @user, :ideas
  end

  test "should serialize settings as JSON" do
    @user.settings = { theme: "dark", notifications: true }
    @user.save!
    @user.reload
    assert_equal({ "theme" => "dark", "notifications" => true }, @user.settings)
  end

  test "topology_settings returns defaults when none stored" do
    @user.save!
    expected = User::DEFAULT_TOPOLOGY_SETTINGS
    assert_equal expected, @user.topology_settings
  end

  test "topology_settings merges stored with defaults" do
    @user.settings = { 'topology_settings' => { 'show_ideas' => false } }
    @user.save!
    assert_equal false, @user.topology_settings['show_ideas']
    assert_equal 'td', @user.topology_settings['default_dag_mode']
  end

  test "update_topology_settings persists allowed keys" do
    @user.save!
    @user.update_topology_settings({ 'show_ideas' => false, 'bloom_strength' => 0.5 })
    @user.reload
    assert_equal false, @user.topology_settings['show_ideas']
    assert_equal 0.5, @user.topology_settings['bloom_strength']
  end

  test "update_topology_settings rejects unknown keys" do
    @user.save!
    @user.update_topology_settings({ 'show_ideas' => false, 'hacker' => 'bad' })
    @user.reload
    assert_nil @user.settings.dig('topology_settings', 'hacker')
  end

  test "list_settings returns defaults when none stored" do
    @user.save!

    assert_equal User::DEFAULT_LIST_SETTINGS, @user.list_settings
  end

  test "update_list_settings persists allowed default view" do
    @user.save!
    @user.update_list_settings({ 'default_view' => 'named', 'hacker' => 'bad' })

    @user.reload
    assert_equal 'named', @user.list_settings['default_view']
    assert_nil @user.settings.dig('list_settings', 'hacker')
  end

  test "topology_overrides_for returns global when no overrides" do
    @user.save!
    resolved = @user.topology_overrides_for(999)
    assert_equal 'td', resolved['default_dag_mode']
  end

  test "topology_overrides_for merges per-topology overrides" do
    @user.settings = {
      'topology_settings' => { 'show_ideas' => true },
      'topology_overrides' => { '42' => { 'show_ideas' => false } }
    }
    @user.save!
    assert_equal false, @user.topology_overrides_for(42)['show_ideas']
    assert_equal true, @user.topology_overrides_for(99)['show_ideas']
  end

  test "update_topology_overrides stores per-topology settings" do
    @user.save!
    @user.update_topology_overrides(42, { 'show_ideas' => false, 'dag_mode' => '' })
    @user.reload
    overrides = @user.settings.dig('topology_overrides', '42')
    assert_equal false, overrides['show_ideas']
    assert_equal '', overrides['dag_mode']
  end

  test "email_settings returns recipients only" do
    @user.save!
    assert_equal '', @user.email_settings['recipients']
  end

  test "update_email_settings only persists recipients" do
    @user.save!
    @user.update_email_settings({ 'recipients' => 'a@b.com', 'hacker' => 'bad' })
    @user.reload
    assert_equal 'a@b.com', @user.email_settings['recipients']
    assert_nil @user.email_settings['hacker']
  end

  test "event_preset_for returns default for event" do
    @user.save!
    assert_equal 'alert', @user.event_preset_for('state_changed')
    assert_equal 'info', @user.event_preset_for('score_changed')
    assert_equal 'neutral', @user.event_preset_for('unknown')
  end

  test "update_event_presets stores valid presets" do
    @user.save!
    @user.update_event_presets({ 'state_changed' => 'info', 'score_changed' => 'digest' })
    @user.reload
    assert_equal 'info', @user.event_preset_for('state_changed')
    assert_equal 'digest', @user.event_preset_for('score_changed')
  end

  test "update_event_presets rejects invalid preset values" do
    @user.save!
    @user.update_event_presets({ 'state_changed' => 'hacker' })
    @user.reload
    assert_equal 'alert', @user.event_preset_for('state_changed')
  end
end
