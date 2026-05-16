require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: 'test@example.com', name: 'Test')
  end

  test "GET settings/topologies renders settings page" do
    get settings_topologies_path
    assert_response :success
  end

  test "GET settings renders display quote field with current quote" do
    @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

    get settings_path

    assert_response :success
    assert_select "textarea[name=?]", "display_settings[quote]" do |elements|
      assert_equal "Focus on the next useful thing.", elements.first.text
    end
  end

  test "GET settings renders configured quote below navigation" do
    @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

    get settings_path

    assert_response :success
    assert_select "body > header.app-header + div.app-quote-banner", text: "Focus on the next useful thing."
  end

  test "PATCH settings updates display quote" do
    patch settings_path, params: {
      display_settings: {
        quote: "  Make the smallest thing that works.  "
      }
    }

    assert_redirected_to settings_path
    @user.reload
    assert_equal "Make the smallest thing that works.", @user.display_quote
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

  test "GET settings/security renders settings for all local unlock checks" do
    get settings_security_path
    assert_response :success
    assert_select "input[name=?]", "typing_lock[enabled]"
    assert_select "input[name=?]", "authenticator_app[enabled]"
    assert_select "input[name=?]", "voice_id[enabled]"
    assert_match(/Voice ID/, response.body)
  end

  test "PATCH settings/security enabling voice id redirects to voice setup" do
    patch settings_security_path, params: {
      typing_lock: { enabled: "0", lock_after_minutes: "5" },
      authenticator_app: { enabled: "0" },
      voice_id: { enabled: "1" }
    }

    assert_redirected_to enroll_voice_id_path(return_to: settings_security_path)
    assert @user.reload.voice_id_enabled?
    refute @user.voice_id_configured?
  end

  test "GET settings/idea-work-tokens renders page" do
    get "/settings/idea-work-tokens"

    assert_response :success
    assert_select "input[name=?]", "idea_work_tokens[enabled]"
  end

  test "PATCH settings/idea-work-tokens updates token access setting" do
    patch "/settings/idea-work-tokens", params: {
      idea_work_tokens: {
        enabled: "1"
      }
    }

    assert_redirected_to "/settings/idea-work-tokens"
    assert @user.reload.idea_work_tokens_enabled?
  end

  test "GET settings/lists renders page" do
    get settings_lists_path
    assert_response :success
  end

  test "PATCH settings/lists updates list settings" do
    patch settings_lists_path, params: {
      list_settings: {
        default_view: "named"
      }
    }

    assert_redirected_to settings_lists_path
    @user.reload
    assert_equal "named", @user.list_settings["default_view"]
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

  test "idea tabs route uses hyphenated path" do
    assert_equal "/settings/idea-tabs", settings_idea_tabs_path

    get "/settings/idea_tabs"
    assert_redirected_to "/settings/idea-tabs"
  end

  test "PATCH settings/idea-tabs updates idea tab settings" do
    patch settings_idea_tabs_path, params: {
      idea_tabs: {
        scores: "1",
        tool: "1"
      }
    }

    assert_redirected_to settings_idea_tabs_path
    @user.reload
    assert_equal true, @user.idea_tab_settings["scores"]
    assert_equal true, @user.idea_tab_settings["tool"]
    assert_equal false, @user.idea_tab_settings["competitor"]
  end

  test "PATCH settings/idea-tabs can reset idea tab settings" do
    @user.update_idea_tab_settings({ "scores" => "0", "tool" => "1" })

    patch settings_idea_tabs_path, params: { reset_idea_tabs: "1" }

    assert_redirected_to settings_idea_tabs_path
    @user.reload
    assert_equal User::DEFAULT_IDEA_TAB_SETTINGS, @user.idea_tab_settings
  end
end
