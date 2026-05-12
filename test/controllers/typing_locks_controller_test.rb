require "test_helper"

class TypingLocksControllerTest < ActionDispatch::IntegrationTest
  SAMPLE_TEXT = "a useful invention starts as a question, then becomes a habit of careful trials."

  def setup
    reset!
    User.find_each { |user| user.update!(settings: { "typing_lock" => { "enabled" => true } }) }
    @user = User.first
  end

  test "protected pages redirect to fingerprint enrollment before first use" do
    get ideas_url

    assert_redirected_to enroll_typing_lock_path(return_to: ideas_path)
  end

  test "protected pages redirect to unlock when fingerprint is configured" do
    @user.store_typing_fingerprint!(fingerprint_for(SAMPLE_TEXT))

    get ideas_url

    assert_redirected_to typing_lock_path(return_to: ideas_path)
  end

  test "enrollment stores fingerprint and unlocks session" do
    get enroll_typing_lock_path
    assert_response :success

    text = TypingTextLibrary.enrollment_text("early-workshop")
    post typing_lock_enrollment_path, params: {
      challenge_id: "early-workshop",
      timing_payload: timing_events_for(text).to_json,
      return_to: ideas_path
    }

    assert_redirected_to ideas_path
    assert_nil flash[:notice]
    assert @user.reload.typing_fingerprint_configured?

    get ideas_path
    assert_response :success
  end

  test "enrollment page does not ask to store or choose another sample" do
    get enroll_typing_lock_path

    assert_response :success
    assert_no_match(/Store Fingerprint/, response.body)
    assert_no_match(/Use another passage/, response.body)
  end

  test "unlock page does not ask for a manual unlock action" do
    @user.store_typing_fingerprint!(fingerprint_for(SAMPLE_TEXT))

    get typing_lock_path

    assert_response :success
    assert_no_match(/value="Unlock"/, response.body)
  end

  test "unlock form opts out of turbo so matched POST response can render" do
    @user.store_typing_fingerprint!(fingerprint_for(SAMPLE_TEXT))

    get typing_lock_path

    assert_response :success
    assert_match(/data-turbo="false"/, response.body)
  end

  test "unlock page shows keyboard delete icon instead of visible Backspace text" do
    @user.store_typing_fingerprint!(fingerprint_for(SAMPLE_TEXT))

    get typing_lock_path

    assert_response :success
    assert_no_match(/>Backspace</, response.body)
    assert_match(/aria-label="Backspace"/, response.body)
    assert_match(/typing-key__backspace-icon/, response.body)
  end

  test "matching unlock sample replaces lock screen with transition before protected pages" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
      return_to: ideas_path
    }

    assert_response :success
    assert_match(/typing-lock-shell--transitioning/, response.body)
    assert_match(/typing-lock-animation--matched/, response.body)
    assert_match(/Fingerprint matched/, response.body)
    assert_no_match(/typing-lock-form/, response.body)
    assert_no_match(/Unlock with your typing rhythm/, response.body)
    assert_no_match(/typing-lock-result/, response.body)
    assert_match(/data-typing-fingerprint-redirect-url-value="#{ideas_path}"/, response.body)
    assert_match(/typing-unlock-animation:complete-&gt;typing-fingerprint#completeUnlockTransition/, response.body)

    get ideas_path
    assert_response :success
  end

  test "activity refresh keeps unlocked session active after original unlock time" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))
    base_time = Time.zone.local(2026, 1, 1, 12, 0, 0)

    travel_to base_time do
      post verify_typing_lock_path, params: {
        challenge_id: "spark-gap",
        timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
        return_to: ideas_path
      }

      assert_response :success
    end

    travel_to base_time + 4.minutes do
      patch typing_lock_activity_path, as: :json
      assert_response :success
    end

    travel_to base_time + 6.minutes do
      get ideas_path
      assert_response :success
    end
  end

  test "manual lock expires unlocked session and redirects to the lock screen" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
      return_to: ideas_path
    }
    assert_response :success

    get ideas_path
    assert_response :success

    post lock_typing_lock_path, params: { return_to: ideas_path }

    assert_redirected_to typing_lock_path(return_to: ideas_path)

    get ideas_path
    assert_redirected_to typing_lock_path(return_to: ideas_path)
  end

  test "unlocked pages expose a manual lock button and keyboard shortcut" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
      return_to: ideas_path
    }
    assert_response :success

    get ideas_path

    assert_response :success
    assert_select "body[data-controller=?]", "typing-activity"
    assert_select "body[data-typing-activity-lock-action-url-value=?]", lock_typing_lock_path(return_to: ideas_path)
    assert_select "body[data-typing-activity-shortcut-value=?]", "Ctrl/Cmd+Shift+L"
    assert_select "form.nav-lock-form[action=?][method=?]", lock_typing_lock_path(return_to: ideas_path), "post"
    assert_select "button.nav-lock-button[title=?]", "Lock (Ctrl/Cmd+Shift+L)", text: /Lock/
  end

  test "failed unlock sample shows decoy score without lock language" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 190, flight: 120).to_json,
      return_to: ideas_path
    }

    assert_response :unprocessable_content
    assert_match(/This is your score/, response.body)
    assert_no_match(/typing-lock-animation--missed/, response.body)
    assert_no_match(/Fingerprint not matched/, response.body)
    assert_no_match(/>Locked</, response.body)
    assert_no_match(/typing-lock-result/, response.body)
    assert_match(/typing-lock-form/, response.body)

    get ideas_path
    assert_redirected_to typing_lock_path(return_to: ideas_path)
  end

  test "settings update can disable lock and change timeout" do
    @user.update_typing_lock_settings("enabled" => "0")

    patch settings_security_path, params: {
      typing_lock: {
        enabled: "0",
        lock_after_minutes: "12"
      }
    }

    assert_redirected_to settings_security_path
    @user.reload
    assert_equal false, @user.typing_lock_enabled?
    assert_equal 720, @user.typing_lock_timeout_seconds
  end

  test "settings update can enable authenticator app and show QR setup" do
    @user.update_typing_lock_settings("enabled" => "0")

    patch settings_security_path, params: {
      typing_lock: {
        enabled: "1",
        lock_after_minutes: "5"
      },
      authenticator_app: {
        enabled: "1"
      }
    }

    assert_redirected_to settings_security_path
    assert @user.reload.authenticator_app_enabled?
    assert_match(/\A[A-Z2-7]{32}\z/, @user.authenticator_app_secret)

    get settings_security_path

    assert_response :success
    assert_select ".authenticator-setup-qr svg"
    assert_match(/Scan this QR code/, response.body)
    assert_match(@user.authenticator_app_secret, response.body)
  end

  test "matching typing sample asks for authenticator code before unlock animation when enabled" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))
    @user.update_authenticator_app_settings("enabled" => "1")

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
      return_to: ideas_path
    }

    assert_response :success
    assert_match(/Authenticator code/, response.body)
    assert_match(/name="authenticator_code"/, response.body)
    assert_match(/name="authenticator_challenge"/, response.body)
    assert_no_match(/typing-lock-animation--matched/, response.body)

    get ideas_path
    assert_redirected_to typing_lock_path(return_to: ideas_path)
  end

  test "valid authenticator code completes the two step unlock" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))
    @user.update_authenticator_app_settings("enabled" => "1")
    travel_time = Time.zone.local(2026, 1, 1, 12, 0, 0)

    travel_to travel_time do
      post verify_typing_lock_path, params: {
        challenge_id: "spark-gap",
        timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
        return_to: ideas_path
      }

      assert_response :success
      assert_match(/Authenticator code/, response.body)
      challenge = css_select('input[name="authenticator_challenge"]').first["value"]

      post verify_authenticator_typing_lock_path, params: {
        authenticator_challenge: challenge,
        authenticator_code: AuthenticatorApp.code(@user.authenticator_app_secret, at: travel_time),
        return_to: ideas_path
      }

      assert_response :success
      assert_match(/typing-lock-shell--transitioning/, response.body)
      assert_match(/typing-lock-animation--matched/, response.body)
      assert_match(/Fingerprint matched/, response.body)

      get ideas_path
      assert_response :success
    end
  end

  test "invalid authenticator code keeps the session locked" do
    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    @user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 91, flight: 41))
    @user.update_authenticator_app_settings("enabled" => "1")

    post verify_typing_lock_path, params: {
      challenge_id: "spark-gap",
      timing_payload: timing_events_for(unlock_text, hold: 94, flight: 44).to_json,
      return_to: ideas_path
    }
    challenge = css_select('input[name="authenticator_challenge"]').first["value"]

    post verify_authenticator_typing_lock_path, params: {
      authenticator_challenge: challenge,
      authenticator_code: "000000",
      return_to: ideas_path
    }

    assert_response :unprocessable_content
    assert_match(/Invalid authenticator code/, response.body)

    get ideas_path
    assert_redirected_to typing_lock_path(return_to: ideas_path)
  end

  private

  def fingerprint_for(text, hold: 90, flight: 40)
    TypingFingerprint.build(events: timing_events_for(text, hold:, flight:), expected_text: text)
  end

  def timing_events_for(text, hold: 88, flight: 42)
    time = 1000.0

    text.chars.each_with_index.map do |key, index|
      duration = hold + (index % 5)
      event = {
        "key" => key,
        "index" => index,
        "down" => time,
        "up" => time + duration
      }
      time += duration + flight + (index % 3)
      event
    end
  end
end
