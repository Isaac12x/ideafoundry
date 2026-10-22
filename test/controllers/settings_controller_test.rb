require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  test "scoring page shows cost scorecard and saves custom scorecards" do
    get settings_scoring_path
    assert_response :success
    assert_select ".scoring-sys-panel__name", text: "Cost scorecard"

    patch settings_scoring_path, params: {
      scoring_weights: { trl: 0.3, difficulty: -0.1, opportunity: 0.4, timing: 0.2 },
      custom_scoring_systems_present: "1",
      custom_scoring_systems: { "a1" => { id: "custom_ab12cd34", name: "Mine", scale_max: 5,
                                           criteria: { "z" => { key: "cdeadbeef", label: "Fun", weight: 1 } } } }
    }
    assert_equal [ "custom_ab12cd34" ], @user.reload.custom_scoring_systems.map { |s| s["id"] }

    get settings_scoring_path
    assert_select "input[name='custom_scoring_systems[0][name]'][value=Mine]"
  end

  test "GET settings/topologies renders settings page" do
    get settings_topologies_path
    assert_response :success
  end

  test "GET settings does not render display quote form" do
    get settings_path
    assert_response :success
    assert_select "textarea[name=?]", "display_settings[quote]", count: 0
  end

  test "GET settings renders Chrome Capture link" do
    get settings_path
    assert_select "a[href=?]", settings_capture_path
  end

  test "GET settings/capture lists recent jobs" do
    @user.capture_jobs.create!(url: "https://example.com/listed")
    get settings_capture_path
    assert_response :success
    assert_select ".capture-job-url", text: "https://example.com/listed"
  end

  test "api keys page has no capture section" do
    get settings_api_keys_path
    assert_response :success
    assert_no_match "Capture via Chrome extension", response.body
  end

  test "api keys page renders create, keys and docs cards with masked key" do
    key = ApiKey.generate(user: @user, name: "Zapier")
    get settings_api_keys_path
    assert_response :success
    assert_select "section.api-card", 3
    assert_select "#api-create-title", "Create"
    assert_select "#api-keys-title", "Your keys"
    assert_select "#api-docs-title", "Docs"
    assert_select "[data-controller='key-reveal'] [data-key-reveal-target='masked']"
    assert_select "button[data-action='key-reveal#toggle'][aria-pressed='false']"
    assert_select "form[action=?]", settings_api_key_destroy_path(key)
    assert_no_match key.raw_token, response.body
    assert_match "/api/v1/capture", response.body
  end

  test "api key creation stores token encrypted and reveal returns it to owner" do
    key = ApiKey.generate(user: @user, name: "Reveal")
    raw = ApiKey.connection.select_value("SELECT token FROM api_keys WHERE id = #{key.id}")
    assert_not_equal key.raw_token, raw
    assert_not_includes raw.to_s, key.raw_token

    get settings_api_key_reveal_path(key)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal key.raw_token, response.parsed_body["token"]
    assert_equal key, ApiKey.authenticate(key.raw_token)
  end

  test "reveal with undecryptable token responds like legacy" do
    key = ApiKey.generate(user: @user, name: "Broken")
    raw = ApiKey.connection.select_value("SELECT token FROM api_keys WHERE id = #{key.id}")
    payload = JSON.parse(raw)
    payload["p"] = Base64.strict_encode64("x" * 64) # breaks the auth tag
    ApiKey.connection.execute(ApiKey.sanitize_sql_array([ "UPDATE api_keys SET token = ? WHERE id = ?", payload.to_json, key.id ]))
    get settings_api_key_reveal_path(key)
    assert_response :success
    assert_nil response.parsed_body["token"]
    assert response.parsed_body["message"].present?
  end

  test "reveal 404s for another user's key" do
    other = User.create!(email: "other-#{SecureRandom.hex(3)}@example.com", name: "Other")
    key = ApiKey.generate(user: other, name: "Theirs")
    get settings_api_key_reveal_path(key)
    assert_response :not_found
  end

  test "reveal for legacy key without stored token returns null" do
    key = ApiKey.generate(user: @user, name: "Legacy")
    key.update_column(:token, nil)
    get settings_api_key_reveal_path(key)
    assert_response :success
    assert_nil response.parsed_body["token"]
  end

  test "settings index wires scroll/last-viewed controller" do
    get settings_path
    assert_select ".settings-container[data-controller='settings-index']"
  end

  test "GET settings renders Display link" do
    get settings_path
    assert_response :success
    assert_select "a[href=?]", settings_display_path
  end

  test "GET settings renders Local Agent link" do
    get settings_path

    assert_response :success
    assert_equal "/settings/ai-agents", settings_local_agent_path
    assert_select "a[href=?]", settings_local_agent_path
  end

  test "layout hides global ask agent form when local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")

    get ideas_path

    assert_response :success
    assert_select ".ask-agent-shell", count: 0
    assert_no_match(/Open Ask Agent/, response.body)
  end

  test "layout hides global ask agent form when local agent is enabled but not live" do
    @user.update_local_agent_settings("enabled" => "1")

    get ideas_path

    assert_response :success
    assert_select ".ask-agent-shell", count: 0
    assert_no_match(/Open Ask Agent/, response.body)
  end

  test "layout renders global ask agent form when local agent is live" do
    @user.update_local_agent_settings("enabled" => "1")
    create_live_local_agent_run

    get ideas_path

    assert_response :success
    assert_select "nav.header-nav .ask-agent-shell", count: 0
    assert_select ".ask-agent-shell form[action=?]", settings_local_agent_questions_path, count: 1
    assert_select ".ask-agent-shell textarea[name=?]", "agent_question[body]"
    assert_select ".ask-agent-shell input[name=?][value=?]", "return_to", "#{ideas_path}?ask_agent=open"
    assert_select ".ask-agent-launcher[aria-controls=?]", "ask_agent_sidebar"
    assert_select ".ask-agent-launcher__invention .ask-agent-invention--bulb", count: 1
    assert_select ".ask-agent-sidebar[role=?]", "dialog"
  end

  test "GET settings/display renders display quote field with current quote" do
    @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

    get settings_display_path

    assert_response :success
    assert_select "textarea[name=?]", "display_settings[quote]" do |elements|
      assert_equal "Focus on the next useful thing.", elements.first.text
    end
  end

  test "GET settings/display shows empty custom quote field and no banner" do
    @user.update!(settings: (@user.settings || {}).except("display_quote"))

    get settings_display_path

    assert_response :success
    # The quote banner is suppressed on settings pages.
    assert_select "div.app-quote-banner", count: 0
    assert_select "textarea[name=?]", "display_settings[quote]" do |elements|
      assert_equal "", elements.first.text
      assert_includes elements.first["placeholder"], "Your mind is for having ideas"
    end
  end

  test "configured quote banner renders on non-settings pages only" do
    @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

    get root_path
    assert_response :success
    assert_select "body > header.app-header ~ div.app-quote-banner", text: /Focus on the next useful thing./

    get settings_display_path
    assert_response :success
    assert_select "div.app-quote-banner", count: 0
  end

  test "PATCH settings updates display quote" do
    patch settings_path, params: {
      display_settings: {
        quote: "  Make the smallest thing that works.  "
      }
    }

    assert_redirected_to settings_display_path
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
    assert_equal false, @user.topology_settings["show_ideas"]
    assert_equal 0.5, @user.topology_settings["bloom_strength"]
    assert_equal "graph", @user.topology_settings["default_view"]
  end

  test "PATCH settings/topologies rejects invalid keys" do
    patch settings_topologies_path, params: {
      topology_settings: { hacker: "bad", show_ideas: "true" }
    }
    assert_redirected_to settings_topologies_path
    @user.reload
    assert_nil @user.settings&.dig("topology_settings", "hacker")
  end

  test "PATCH settings/topologies stores topology default template fields" do
    topology = @user.topologies.create!(name: "Software #{SecureRandom.hex(4)}", topology_type: :custom)

    patch settings_topologies_path, params: {
      topology_settings: { show_ideas: "true" },
      topology_template_fields: {
        topology.id.to_s => {
          "0" => {
            name: "github_url",
            label: "GitHub URL",
            type: "url",
            required: "0",
            placeholder: "https://github.com/acme/project"
          }
        }
      }
    }

    assert_redirected_to settings_topologies_path
    field = topology.reload.default_field_definitions.first
    assert_equal "github_url", field["name"]
    assert_equal "url", field["type"]
    assert_equal "https://github.com/acme/project", field["placeholder"]
  ensure
    topology&.destroy
  end

  test "GET settings/github renders github credentials page" do
    get settings_github_path

    assert_response :success
    assert_select "input[name=?]", "github_settings[token]"
  end

  test "PATCH settings/github stores github token" do
    patch settings_github_path, params: {
      github_settings: {
        token: "ghp_secret_token"
      }
    }

    assert_redirected_to settings_github_path
    assert @user.reload.github_configured?
    assert_equal "ghp_secret_token", @user.github_token
  end

  test "GET settings/email renders page" do
    get settings_email_path
    assert_response :success
  end

  test "GET settings/security renders settings for all local unlock checks" do
    get settings_security_path
    assert_response :success
    assert_select "input[name=?]", "typing_lock[enabled]"
    assert_select "input[name=?][value=?]", "typing_lock[failed_unlock_cooldown_minutes]", "5"
    assert_select "input[name=?]", "authenticator_app[enabled]"
    assert_select "input[name=?]", "voice_id[enabled]"
    assert_select "input[name=?]", "mobile_uplink[enabled]"
    assert_match(/Voice ID/, response.body)
    assert_match(/Mobile Uplink/, response.body)
  end

  test "PATCH settings/security enabling mobile uplink renders install and pairing QR setup" do
    patch settings_security_path, params: {
      typing_lock: {
        enabled: "0",
        lock_after_minutes: "5"
      },
      authenticator_app: {
        enabled: "0"
      },
      voice_id: {
        enabled: "0"
      },
      mobile_uplink: {
        enabled: "1"
      }
    }

    assert_redirected_to settings_security_path
    assert @user.reload.mobile_uplink_enabled?
    assert_match(/\A[A-Za-z0-9_-]{24}\z/, @user.mobile_uplink_id)

    get settings_security_path

    assert_response :success
    assert_select ".mobile-uplink-install-qr svg"
    assert_select ".mobile-uplink-pairing-qr svg"
    assert_match(/Install the mobile uplink app/, response.body)
    assert_match(@user.mobile_uplink_id, response.body)
    assert_match(/encrypts data multiple times before it leaves/, response.body)
  end

  test "GET settings/security renders passphrase and backup acknowledgements for plaintext SQLite" do
    root = Rails.root.join("tmp/settings_sqlcipher_controller_test_#{SecureRandom.hex(6)}")
    database_path = root.join("production.sqlite3")
    FileUtils.mkdir_p(root)
    create_plaintext_sqlite_database(database_path)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ database_path.to_s ]) do
      get settings_security_path
    end

    assert_response :success
    assert_select ".security-database-encryption" do
      assert_select "strong", text: "Needs encryption"
      assert_select "form[action=?][method=?]", settings_security_encrypt_database_path, "post"
      assert_select "input[name=?][type=?]", "database_encryption[passphrase]", "password"
      assert_select "input[name=?][type=?]", "database_encryption[passphrase_confirmation]", "password"
      assert_select "input[name=?][type=?]", "database_encryption[saved_primary]", "checkbox"
      assert_select "input[name=?][type=?]", "database_encryption[saved_secondary]", "checkbox"
      assert_select "input[type=?][value=?]", "submit", "Encrypt SQLite Databases"
    end
  ensure
    FileUtils.rm_rf(root) if root&.exist?
  end

  test "POST settings/security/encrypt-database refuses to encrypt without a matching passphrase and two saved-copy acknowledgements" do
    # Mismatched confirmation is rejected by the validation guard before any
    # database migration is attempted.
    post settings_security_encrypt_database_path, params: {
      database_encryption: {
        passphrase: "one good passphrase",
        passphrase_confirmation: "another different passphrase",
        saved_primary: "1",
        saved_secondary: "1"
      }
    }

    assert_redirected_to settings_security_path
    assert_match(/Passphrase confirmation does not match/, flash[:alert])
  end

  test "POST settings/security/encrypt-database refuses to encrypt until the user confirms two saved passphrase copies" do
    # Missing the second saved-copy acknowledgement is rejected by the validation
    # guard before any database migration is attempted.
    post settings_security_encrypt_database_path, params: {
      database_encryption: {
        passphrase: "correct horse battery staple",
        passphrase_confirmation: "correct horse battery staple",
        saved_primary: "1",
        saved_secondary: "0"
      }
    }

    assert_redirected_to settings_security_path
    assert_match(/Save the passphrase in more than one place/, flash[:alert])
  end

  test "POST settings/security/encrypt-database encrypts configured plaintext SQLite with the UI passphrase" do
    root = Rails.root.join("tmp/settings_sqlcipher_controller_test_#{SecureRandom.hex(6)}")
    database_path = root.join("production.sqlite3")
    backup_dir = root.join("backups")
    FileUtils.mkdir_p(root)
    create_plaintext_sqlite_database(database_path)

    with_recovery_passphrase_file(root.join("recovery_passphrase.key")) do
      with_sqlcipher_backup_dir(backup_dir) do
        SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ database_path.to_s ]) do
          post settings_security_encrypt_database_path, params: {
            database_encryption: {
              passphrase: "correct horse battery staple",
              passphrase_confirmation: "correct horse battery staple",
              saved_primary: "1",
              saved_secondary: "1"
            }
          }
        end
      end
    end

    assert_redirected_to settings_security_path
    assert_match(/Encrypted 1 SQLite database/, flash[:notice])
    assert_equal "correct horse battery staple", JSON.parse(File.read(root.join("recovery_passphrase.key")))["passphrase"]
    refute_equal "SQLite format 3\0", File.binread(database_path, 16)
    assert_nil Dir[backup_dir.join("production.sqlite3.*.plaintext").to_s].first, "plaintext backup must be deleted after successful migration"
  ensure
    FileUtils.rm_rf(root) if root&.exist?
  end

  test "GET settings/security renders redo actions on each fingerprint row" do
    original_settings = @user.settings.deep_dup
    @user.update!(settings: {
      "typing_lock" => {
        "enabled" => false,
        "fingerprint" => { "sample_count" => 3, "features" => {} }
      },
      "voice_id" => {
        "enabled" => false,
        "fingerprint" => { "sample_count" => 3, "features" => {} }
      }
    })

    get settings_security_path

    assert_response :success
    assert_select ".typing-settings-actions a", text: /Redo Fingerprint/, count: 0
    assert_select ".security-fingerprint-row--typing" do
      assert_select "a[href=?]", enroll_typing_lock_path(return_to: settings_security_path), text: "Redo Typing Fingerprint", count: 1
    end
    assert_select ".security-fingerprint-row--voice" do
      assert_select "a[href=?]", enroll_voice_id_path(return_to: settings_security_path), text: "Redo Voice ID", count: 1
    end
  ensure
    @user.update!(settings: original_settings) if defined?(original_settings)
  end

  test "PATCH settings/security enabling voice id redirects to voice setup" do
    patch settings_security_path, params: {
      typing_lock: { enabled: "0", lock_after_minutes: "5" },
      authenticator_app: { enabled: "0" },
      voice_id: { enabled: "1" }
    }

    assert_redirected_to enroll_voice_id_path(return_to: settings_security_path)
    assert @user.reload.voice_id_requested?
    refute @user.voice_id_configured?
  end

  test "PATCH settings/security as json returns voice id enrollment redirect" do
    patch settings_security_path, as: :json, params: {
      typing_lock: { enabled: "0", lock_after_minutes: "5" },
      authenticator_app: { enabled: "0" },
      voice_id: { enabled: "1" }
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["saved"]
    assert_equal enroll_voice_id_path(return_to: settings_security_path), body["redirect_to"]
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

  test "PATCH settings/idea-work-tokens as json updates token access setting" do
    patch settings_idea_work_tokens_path, as: :json, params: {
      idea_work_tokens: {
        enabled: "1"
      }
    }

    assert_response :success
    assert_equal({ "saved" => true }, JSON.parse(response.body))
    assert @user.reload.idea_work_tokens_enabled?
  end

  test "GET settings/ai-agents renders local agent controls" do
    get settings_local_agent_path

    assert_response :success
    assert_select "input[name=?]", "local_agent[enabled]"
    assert_select "input[name=?]", "local_agent[destructive_actions_enabled]"
    assert_select "input[name=?]", "local_agent[sleep_seconds]"
    assert_select "input[name=?]", "local_agent[max_actions_per_cycle]"
    assert_select "input[name=?]", "local_agent[model]", count: 0
    assert_select "input[name=?]", "local_agent[base_url]", count: 0
    assert_select "form[action=?]", settings_local_agent_run_now_path
  end

  test "GET settings/ai-agents omits the local question form when local agent is live" do
    @user.update_local_agent_settings("enabled" => "1")
    create_live_local_agent_run

    get settings_local_agent_path

    assert_response :success
    assert_select ".local-agent-questions", count: 0
    assert_select ".ask-agent-shell form[action=?]", settings_local_agent_questions_path, count: 1
    assert_select ".ask-agent-shell textarea[name=?]", "agent_question[body]"
  end

  test "GET settings/ai-agents omits the local question form when local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")

    get settings_local_agent_path

    assert_response :success
    assert_select ".local-agent-questions", count: 0
    assert_select ".ask-agent-shell", count: 0
  end

  test "POST settings/ai-agents/questions queues a local agent question" do
    @user.update_local_agent_settings("enabled" => "1")

    assert_difference -> { @user.agent_events.where(event_type: "question").count }, 1 do
      post settings_local_agent_questions_path, params: {
        agent_question: {
          body: "Which idea should I focus on next?"
        }
      }
    end

    assert_redirected_to settings_local_agent_path(ask_agent: "open")
    event = @user.agent_events.where(event_type: "question").recent.first
    assert_equal "Which idea should I focus on next?", event.payload["question"]
    assert_equal "pending", event.payload["status"]
  end

  test "POST settings/ai-agents/questions returns to provided page" do
    @user.update_local_agent_settings("enabled" => "1")

    assert_difference -> { @user.agent_events.where(event_type: "question").count }, 1 do
      post settings_local_agent_questions_path, params: {
        return_to: ideas_path,
        agent_question: {
          body: "What changed recently?"
        }
      }
    end

    assert_redirected_to ideas_path
  end

  test "POST settings/ai-agents/questions rejects questions while local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")

    assert_no_difference -> { @user.agent_events.where(event_type: "question").count } do
      post settings_local_agent_questions_path, params: {
        agent_question: {
          body: "What changed recently?"
        }
      }
    end

    assert_redirected_to settings_local_agent_path
  end

  test "GET settings/local-agent redirects to ai agents settings" do
    get "/settings/local-agent"

    assert_redirected_to settings_local_agent_path
  end

  test "PATCH settings/ai-agents updates local agent settings" do
    patch settings_local_agent_path, params: {
      local_agent: {
        enabled: "1",
        destructive_actions_enabled: "0",
        sleep_seconds: "9",
        max_actions_per_cycle: "4",
        model: "local-model",
        base_url: "http://localhost:1234/v1",
        hacker: "bad"
      }
    }

    assert_redirected_to settings_local_agent_path
    settings = @user.reload.local_agent_settings
    assert_equal true, settings["enabled"]
    assert_equal false, settings["destructive_actions_enabled"]
    assert_equal 9, settings["sleep_seconds"]
    assert_equal 4, settings["max_actions_per_cycle"]
    refute_includes settings, "model"
    refute_includes settings, "base_url"
    assert_nil @user.settings.dig("local_agent", "model")
    assert_nil @user.settings.dig("local_agent", "base_url")
    assert_nil @user.settings.dig("local_agent", "hacker")
  end

  test "PATCH settings/ai-agents as json updates local agent settings" do
    patch settings_local_agent_path, as: :json, params: {
      local_agent: {
        enabled: "1",
        destructive_actions_enabled: "0",
        sleep_seconds: "9",
        max_actions_per_cycle: "4"
      }
    }

    assert_response :success
    assert_equal true, JSON.parse(response.body)["saved"]
    settings = @user.reload.local_agent_settings
    assert_equal true, settings["enabled"]
    assert_equal false, settings["destructive_actions_enabled"]
  end

  test "GET settings/ai-agents renders pending recommendations" do
    idea = @user.ideas.create!(title: "Recommendation target", state: :triage)
    recommendation = @user.agent_recommendations.create!(
      target: idea,
      action: "transition_idea",
      risk_level: "high",
      reasoning: "Ready to ship",
      payload: { "idea_id" => idea.id, "state" => "shipped" }
    )

    get settings_local_agent_path

    assert_response :success
    assert_select "[data-agent-recommendation-id=?]", recommendation.id.to_s
    assert_select "form[action=?]", settings_local_agent_recommendation_approve_path(recommendation)
    assert_select "form[action=?]", settings_local_agent_recommendation_dismiss_path(recommendation)
  end

  test "POST dismiss local agent recommendation redirects to safe return path" do
    idea = @user.ideas.create!(title: "Inline recommendation target", state: :triage)
    recommendation = @user.agent_recommendations.create!(
      target: idea,
      action: "update_idea",
      risk_level: "medium",
      reasoning: "Needs review",
      payload: { "idea_id" => idea.id, "title" => "Updated" }
    )

    post settings_local_agent_recommendation_dismiss_path(recommendation),
         params: { return_to: idea_path(idea, anchor: "agent-suggestions") }

    assert_redirected_to idea_path(idea, anchor: "agent-suggestions")
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
      email_settings: { recipients: "a@b.com" },
      event_presets: { state_changed: "info", score_changed: "digest" },
      notification_triggers: %w[state_changed]
    }
    assert_redirected_to settings_email_path
    @user.reload
    assert_equal "a@b.com", @user.email_settings["recipients"]
    assert_equal "info", @user.event_preset_for("state_changed")
    assert_equal "digest", @user.event_preset_for("score_changed")
    assert_equal [ "state_changed" ], @user.notification_triggers
  end

  test "PATCH settings/notifications as json saves toggle preferences" do
    patch settings_notifications_path, as: :json, params: {
      notification_triggers: %w[state_changed],
      notification_content: {
        state_changed: {
          include_scores: "false",
          include_description: "true"
        }
      }
    }

    assert_response :success
    assert_equal({ "saved" => true }, JSON.parse(response.body))
    @user.reload
    assert_equal [ "state_changed" ], @user.notification_triggers
    assert_equal "false", @user.notification_content.dig("state_changed", "include_scores")
    assert_equal "true", @user.notification_content.dig("state_changed", "include_description")
  end

  test "PATCH settings/backup as json saves on off settings" do
    patch settings_backup_path, as: :json, params: {
      backup_settings: {
        frequency: "daily",
        retention_days: "14",
        max_backups: "3",
        auto_cleanup: "false",
        email_notification: "true"
      }
    }

    assert_response :success
    assert_equal({ "saved" => true }, JSON.parse(response.body))
    settings = @user.reload.backup_settings
    assert_equal "false", settings["auto_cleanup"]
    assert_equal "true", settings["email_notification"]
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

  test "PATCH settings/idea-tabs as json updates tab visibility" do
    patch settings_idea_tabs_path, as: :json, params: {
      idea_tabs: {
        scores: "1",
        tool: "1"
      }
    }

    assert_response :success
    assert_equal({ "saved" => true }, JSON.parse(response.body))
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

  test "keyboard shortcuts persist per user and are serialized into the page" do
    get settings_shortcuts_path
    assert_response :success

    patch settings_shortcuts_path, params: { keyboard_shortcuts: { save: "Ctrl/Cmd+Y", go_plan: "g x", edit: "" } }
    assert_redirected_to settings_shortcuts_path
    assert_equal({ "save" => "Ctrl/Cmd+Y", "go_plan" => "g x" }, @user.reload.keyboard_shortcuts)
    assert_equal "Ctrl/Cmd+Y", @user.shortcut_binding("save")
    assert_equal "e", @user.shortcut_binding("edit")

    get settings_path
    assert_select "body[data-shortcut-overrides*='Ctrl/Cmd+Y']"
  end

  test "keyboard shortcuts reject collisions, bad bindings and unknown ids" do
    {
      { save: "Ctrl/Cmd+L" } => "Save the current form",       # collides with the lock default
      { save: "Ctrl/Cmd+K" } => "Search ideas",                 # collides with another default
      { save: "ctrl+s" } => "not a valid binding",
      { save: "Ctrl/Cmd+#{"x" * 40}" } => "not a valid binding",
      { edit: "g" } => "starts a sequence",
      { save: "Ctrl/Cmd+Y", submit: "Ctrl/Cmd+Y" } => "share",
      { lock: "x" } => "needs Ctrl/Cmd or Alt",
      { search: "g x" } => "needs Ctrl/Cmd or Alt",
      { lock: "Ctrl/Cmd+S" } => "share",
      { lock: "Ctrl/Cmd+Enter" } => "share",
      { lock: "Shift+Ctrl/Cmd+Y" } => "not a valid binding",   # canonical modifier order only
      { edit: "Alt+1" } => "reserved",
      { edit: "x y z" } => "not a valid binding",
      { edit: "g x" } => "only for navigation",
      { edit: "Shift+?" } => "Shift is implied",
      { edit: "Enter" } => "needs Ctrl/Cmd or Alt",
      { edit: "ArrowDown" } => "needs Ctrl/Cmd or Alt",
      { edit: "F5" } => "needs Ctrl/Cmd or Alt"
    }.each do |params, message|
      patch settings_shortcuts_path, params: { keyboard_shortcuts: params }
      assert_response :unprocessable_content
      assert_includes response.body, message
      assert_empty @user.reload.keyboard_shortcuts
    end

    assert_not @user.update_keyboard_shortcuts("bogus" => "Ctrl/Cmd+Y")

    @user.update_keyboard_shortcuts("save" => "Ctrl/Cmd+Y")
    [ { keyboard_shortcuts: "oops" }, {} ].each do |bad| # non-hash or missing: no 500, nothing wiped
      patch settings_shortcuts_path, params: bad
      assert_response :unprocessable_content
      assert_equal({ "save" => "Ctrl/Cmd+Y" }, @user.reload.keyboard_shortcuts)
    end
    @user.update_keyboard_shortcuts({})

    assert @user.update_keyboard_shortcuts("edit" => "X")
    assert_equal "x", @user.keyboard_shortcuts["edit"]

    patch settings_shortcuts_path, params: { keyboard_shortcuts: { save: "Ctrl/Cmd+K" } }
    assert_select "input[name='keyboard_shortcuts[save]'][value='Ctrl/Cmd+K']" # typed value survives a 422
  end

  test "reset all clears custom shortcuts" do
    @user.update_keyboard_shortcuts("save" => "Ctrl/Cmd+Y")
    get settings_shortcuts_path
    assert_select "small", text: /custom/
    patch settings_shortcuts_path, params: { reset_all: "1" }
    assert_empty @user.reload.keyboard_shortcuts
  end

  test "lock can never take the Save or Submit keys, even once those are moved" do
    assert_not @user.update_keyboard_shortcuts("save" => "Ctrl/Cmd+Y", "lock" => "Ctrl/Cmd+S")
    assert_not @user.update_keyboard_shortcuts("submit" => "Ctrl/Cmd+Y", "lock" => "Ctrl/Cmd+Enter")
  end

  test "user can rebind lock and then reuse its default" do
    assert @user.update_keyboard_shortcuts("lock" => "Ctrl/Cmd+Shift+L", "save" => "Ctrl/Cmd+L")
    assert_equal "Ctrl/Cmd+Shift+L", @user.shortcut_binding("lock")
  end

  test "JS default shortcut table is readable by the server" do
    assert_equal "Ctrl/Cmd+L", User::DEFAULT_SHORTCUTS.dig("lock", "key")
  end

  test "GET settings/display renders display page" do
    get settings_display_path
    assert_response :success
  end

  test "PATCH settings/display updates contrast and redirects to display page" do
    patch settings_display_path, params: {
      display_settings: { quote: "Keep it simple.", contrast: "120" }
    }
    assert_redirected_to settings_display_path
    @user.reload
    assert_equal 120, @user.display_contrast
    assert_equal "Keep it simple.", @user.display_quote
  end

  test "PATCH settings/display persists quote library, per-page quotes, and nav visibility" do
    patch settings_display_path, params: {
      display_settings: {
        quote: "Base quote",
        quote_library: [ "Alpha", "", "Beta" ],
        quote_pages: { "ideas" => "1", "kb" => "none" },
        nav_visible: { "ideas" => "1", "plan" => "1" }
      }
    }
    assert_redirected_to settings_display_path
    @user.reload

    assert_equal %w[Alpha Beta], @user.quote_library
    assert_equal "Beta", @user.quote_for_page("ideas")
    assert_nil @user.quote_for_page("kb")
    assert @user.nav_item_visible?("ideas")
    assert_not @user.nav_item_visible?("topologies")  # absent from nav_visible -> hidden
  end

  test "GET settings/display renders per-page quote selects and nav toggles" do
    get settings_display_path
    assert_response :success
    assert_select "textarea[name=?]", "display_settings[quote_library][]"
    assert_select "select[name=?]", "display_settings[quote_pages][ideas]"
    assert_select "input[type=checkbox][name=?]", "display_settings[nav_visible][kb]"
  end

  test "display_contrast returns 100 by default" do
    @user.update!(settings: {})
    assert_equal 100, @user.display_contrast
  end

  test "display_contrast migrates legacy 'high' to 130" do
    @user.update!(settings: { "display_contrast" => "high" })
    assert_equal 130, @user.display_contrast
  end

  test "display_contrast migrates legacy 'normal' to 100" do
    @user.update!(settings: { "display_contrast" => "normal" })
    assert_equal 100, @user.display_contrast
  end

  test "display_contrast returns stored integer value" do
    @user.update!(settings: { "display_contrast" => "120" })
    assert_equal 120, @user.display_contrast
  end

  test "display_contrast clamps out-of-range value to 100" do
    @user.update!(settings: { "display_contrast" => "999" })
    assert_equal 100, @user.display_contrast
  end

  test "GET settings/kb renders the drives section and mount form" do
    get settings_kb_path
    assert_response :success
    assert_select "h3", text: "Drives"
    assert_select "form[action=?]", settings_kb_mount_drive_path
    assert_select "select[data-kb-drives-target='volume']"
  end

  test "PATCH settings/kb persists drives alongside folders" do
    original = @user.settings.deep_dup
    patch settings_kb_path, params: { kb_folders: [], kb_drives: [ "/Volumes/Archive" ] }

    assert_redirected_to settings_kb_path
    assert_equal [ "/Volumes/Archive" ], @user.reload.kb_drives
  ensure
    @user.update!(settings: original)
  end

  test "POST settings/kb/mount-drive rejects a non-share url" do
    before = @user.kb_drives
    post settings_kb_mount_drive_path, params: { url: "https://evil.example.com" }

    assert_redirected_to settings_kb_path
    assert_equal before, @user.reload.kb_drives
    assert_match(/share url/i, flash[:alert])
  end

  private

  def create_live_local_agent_run
    @user.agent_runs.create!(
      status: :running,
      started_at: 1.minute.ago,
      last_heartbeat_at: Time.current
    )
  end

  def create_plaintext_sqlite_database(path)
    db = SQLite3::Database.new(path.to_s)
    db.execute("CREATE TABLE ideas (id integer primary key, title text)")
    db.execute("INSERT INTO ideas (title) VALUES (?)", [ "Encrypted from settings" ])
  ensure
    db&.close
  end

  def with_sqlcipher_backup_dir(path)
    original = ENV["IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR"]
    ENV["IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR"] = path.to_s
    yield
  ensure
    if original.nil?
      ENV.delete("IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR")
    else
      ENV["IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR"] = original
    end
  end

  def with_recovery_passphrase_file(path)
    original_file = ENV[RecoverySecret::PASSPHRASE_FILE_ENV]
    original_passphrase = ENV[RecoverySecret::PASSPHRASE_ENV]
    ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = path.to_s
    ENV.delete(RecoverySecret::PASSPHRASE_ENV)
    yield
  ensure
    if original_file.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_FILE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = original_file
    end

    if original_passphrase.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_ENV] = original_passphrase
    end
  end
end
