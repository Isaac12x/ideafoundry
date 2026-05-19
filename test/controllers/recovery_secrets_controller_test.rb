require "test_helper"

class RecoverySecretsControllerTest < ActionDispatch::IntegrationTest
  test "GET recovery secret renders passphrase form" do
    get recovery_secret_path(return_to: settings_security_path)

    assert_response :success
    assert_select "form[action=?][method=?]", recovery_secret_path, "post"
    assert_select "input[type=?][name=?]", "password", "recovery_passphrase"
    assert_select "input[type=?][name=?][value=?]", "hidden", "return_to", settings_security_path
  end

  test "POST recovery secret redirects to safe return path without a success notice" do
    post recovery_secret_path, params: {
      recovery_passphrase: "typed in the UI",
      return_to: settings_security_path
    }

    assert_redirected_to settings_security_path
    assert_nil flash[:notice]
  end

  test "POST recovery secret never shows success notice on the locked page" do
    user = User.first
    user.update!(settings: {
      "typing_lock" => {
        "enabled" => true,
        "fingerprint" => "configured"
      }
    })

    post recovery_secret_path, params: {
      recovery_passphrase: "typed in the UI",
      return_to: root_path
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_match(/Typing rhythm score/, response.body)
    assert_no_match(/Encrypted data unlocked\./, response.body)
    assert_select ".alert.alert-success", count: 0
  end

  test "POST recovery secret persists the verified passphrase for future app boots" do
    root = Rails.root.join("tmp/recovery_secret_controller_test_#{SecureRandom.hex(6)}")
    path = root.join("recovery_passphrase.key")

    with_recovery_passphrase_file(path) do
      post recovery_secret_path, params: {
        recovery_passphrase: "typed once on this node",
        return_to: root_path
      }

      assert_redirected_to root_path
      assert_equal "typed once on this node", File.read(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "POST recovery secret rejects blank passphrase" do
    post recovery_secret_path, params: {
      recovery_passphrase: "",
      return_to: settings_security_path
    }

    assert_response :unprocessable_content
    assert_select ".recovery-secret-error", text: "Enter the recovery passphrase to continue."
  end

  private

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
