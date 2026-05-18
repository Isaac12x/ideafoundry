require "test_helper"
require Rails.root.join("db/migrate/20260517000000_encrypt_user_security_settings")

class EncryptUserSecuritySettingsTest < ActiveSupport::TestCase
  test "up does not require recovery passphrase before user configures database encryption" do
    user = User.first || User.create!(email: "migration-test@example.com", name: "Migration Test")
    original_settings = user.settings.deep_dup

    user.update!(settings: {
      "typing_lock" => {
        "enabled" => true,
        "fingerprint" => { "sample_count" => 3, "features" => { "latency" => 1.2 } }
      },
      "authenticator_app" => {
        "enabled" => true,
        "secret" => "plaintext-authenticator-secret"
      },
      "voice_id" => {
        "enabled" => true,
        "fingerprint" => { "sample_count" => 3, "features" => { "pitch" => 0.8 } }
      }
    })

    with_recovery_env_cleared do
      Rails.env.stub(:production?, true) do
        assert_nothing_raised do
          EncryptUserSecuritySettings.new.up
        end
      end
    end

    user.reload
    assert_equal({ "sample_count" => 3, "features" => { "latency" => 1.2 } }, user.settings.dig("typing_lock", "fingerprint"))
    assert_nil user.settings.dig("typing_lock", "fingerprint_ciphertext")
    assert_equal "plaintext-authenticator-secret", user.settings.dig("authenticator_app", "secret")
    assert_nil user.settings.dig("authenticator_app", "secret_ciphertext")
    assert_equal({ "sample_count" => 3, "features" => { "pitch" => 0.8 } }, user.settings.dig("voice_id", "fingerprint"))
    assert_nil user.settings.dig("voice_id", "fingerprint_ciphertext")
  ensure
    user.update!(settings: original_settings) if defined?(user) && user&.persisted?
  end

  private

  def with_recovery_env_cleared
    original_values = {
      RecoverySecret::PASSPHRASE_ENV => ENV[RecoverySecret::PASSPHRASE_ENV],
      RecoverySecret::PASSPHRASE_FILE_ENV => ENV[RecoverySecret::PASSPHRASE_FILE_ENV],
      RecoverySecret::LEGACY_ENV => ENV[RecoverySecret::LEGACY_ENV]
    }

    original_values.each_key { |key| ENV.delete(key) }
    yield
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
