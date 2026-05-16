require "test_helper"

class AuthenticatorAppTest < ActiveSupport::TestCase
  RFC_6238_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  test "generates six digit TOTP codes from a base32 secret" do
    assert_equal "287082", AuthenticatorApp.code(RFC_6238_SECRET, at: Time.at(59))
  end

  test "verifies codes within the adjacent time window" do
    current_code = AuthenticatorApp.code(RFC_6238_SECRET, at: Time.at(59))
    previous_code = AuthenticatorApp.code(RFC_6238_SECRET, at: Time.at(29))

    assert AuthenticatorApp.verify_code(RFC_6238_SECRET, current_code, at: Time.at(59))
    assert AuthenticatorApp.verify_code(RFC_6238_SECRET, previous_code, at: Time.at(59))
    refute AuthenticatorApp.verify_code(RFC_6238_SECRET, "000000", at: Time.at(59))
  end

  test "generates authenticator-compatible base32 secrets" do
    assert_match(/\A[A-Z2-7]{32}\z/, AuthenticatorApp.generate_secret)
  end
end
