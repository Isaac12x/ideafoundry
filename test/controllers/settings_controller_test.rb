require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: 'test@example.com', name: 'Test')
  end

  test "GET settings/topologies renders settings page" do
    get settings_topologies_path
    assert_response :success
  end

  test "PATCH settings/topologies updates topology settings" do
    patch settings_topologies_path, params: {
      topology_settings: {
        show_ideas: "false",
        bloom_strength: "0.5",
        default_view: "graph"
      }
    }
    assert_redirected_to settings_topologies_path
    @user.reload
    assert_equal false, @user.topology_settings['show_ideas']
    assert_equal 0.5, @user.topology_settings['bloom_strength']
    assert_equal 'graph', @user.topology_settings['default_view']
  end

  test "PATCH settings/topologies rejects invalid keys" do
    patch settings_topologies_path, params: {
      topology_settings: { hacker: "bad", show_ideas: "true" }
    }
    assert_redirected_to settings_topologies_path
    @user.reload
    assert_nil @user.settings&.dig('topology_settings', 'hacker')
  end

  test "GET settings/email renders page" do
    get settings_email_path
    assert_response :success
  end

  test "PATCH settings/notifications saves recipients and presets" do
    patch settings_notifications_path, params: {
      email_settings: { recipients: 'a@b.com' },
      event_presets: { state_changed: 'info', score_changed: 'digest' },
      notification_triggers: %w[state_changed]
    }
    assert_redirected_to settings_email_path
    @user.reload
    assert_equal 'a@b.com', @user.email_settings['recipients']
    assert_equal 'info', @user.event_preset_for('state_changed')
    assert_equal 'digest', @user.event_preset_for('score_changed')
    assert_equal ['state_changed'], @user.notification_triggers
  end
end
