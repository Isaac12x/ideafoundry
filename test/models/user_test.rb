require "test_helper"

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

  test "typing fingerprint can be stored and cleared" do
    user = users(:one)
    fingerprint = { "version" => 1, "keys" => { "a" => { "mean" => 90 } } }

    assert user.store_typing_fingerprint!(fingerprint)
    assert user.typing_fingerprint_configured?
    assert_equal fingerprint, user.typing_fingerprint

    assert user.clear_typing_fingerprint!
    refute user.typing_fingerprint_configured?
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

    secret = user.authenticator_app_secret

    assert user.update_authenticator_app_settings("enabled" => "1")
    assert_equal secret, user.authenticator_app_secret

    assert user.update_authenticator_app_settings("enabled" => "0")
    refute user.authenticator_app_enabled?
    refute user.authenticator_app_configured?
    assert_nil user.authenticator_app_secret
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
