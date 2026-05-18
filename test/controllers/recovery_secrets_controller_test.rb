require "test_helper"

class RecoverySecretsControllerTest < ActionDispatch::IntegrationTest
  test "GET recovery secret renders passphrase form" do
    get recovery_secret_path(return_to: settings_security_path)

    assert_response :success
    assert_select "form[action=?][method=?]", recovery_secret_path, "post"
    assert_select "input[type=?][name=?]", "password", "recovery_passphrase"
    assert_select "input[type=?][name=?][value=?]", "hidden", "return_to", settings_security_path
  end

  test "POST recovery secret redirects to safe return path" do
    post recovery_secret_path, params: {
      recovery_passphrase: "typed in the UI",
      return_to: settings_security_path
    }

    assert_redirected_to settings_security_path
    assert_equal "Encrypted data unlocked.", flash[:notice]
  end

  test "POST recovery secret rejects blank passphrase" do
    post recovery_secret_path, params: {
      recovery_passphrase: "",
      return_to: settings_security_path
    }

    assert_response :unprocessable_content
    assert_select ".recovery-secret-error", text: "Enter the recovery passphrase to continue."
  end
end
