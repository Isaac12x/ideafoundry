require "test_helper"

class RecoverySecretTest < ActiveSupport::TestCase
  test "request scoped passphrase satisfies required secret in production" do
    with_recovery_env_cleared do
      Rails.env.stub(:production?, true) do
        assert_raises(RecoverySecret::Missing) { RecoverySecret.required! }

        RecoverySecret.with("typed in the UI") do
          assert_equal "typed in the UI", RecoverySecret.required!
        end
      end
    end
  end

  test "configured environment passphrase takes precedence over request scoped passphrase" do
    original = ENV[RecoverySecret::PASSPHRASE_ENV]
    ENV[RecoverySecret::PASSPHRASE_ENV] = "from env"

    RecoverySecret.with("from UI") do
      assert_equal "from env", RecoverySecret.required!
    end
  ensure
    if original.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_ENV] = original
    end
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
