require "test_helper"

class RecoverySecretTest < ActiveSupport::TestCase
  test "request scoped passphrase satisfies required secret in production" do
    with_recovery_env_cleared do
      Rails.env.stub(:production?, true) do
        error = assert_raises(RecoverySecret::Missing) { RecoverySecret.required! }
        assert_equal "Enter the recovery passphrase in /settings/security before opening encrypted data", error.message

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

  test "persisted user passphrase file unlocks production without prompting every session on same app node" do
    with_recovery_env_cleared do
      path = Rails.root.join("tmp/recovery_secret_test_#{SecureRandom.hex(6)}.key")

      RecoverySecret.stub(:user_passphrase_file_path, path) do
        RecoverySecret.stub(:app_node_id, "this-node") do
          RecoverySecret.persist_user_passphrase!("persisted passphrase")
          ENV.delete(RecoverySecret::PASSPHRASE_ENV)

          Rails.env.stub(:production?, true) do
            assert_equal "persisted passphrase", RecoverySecret.required!
          end
        end
      end
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end

  test "persisted user passphrase is ignored after app node changes" do
    with_recovery_env_cleared do
      path = Rails.root.join("tmp/recovery_secret_test_#{SecureRandom.hex(6)}.key")

      RecoverySecret.stub(:user_passphrase_file_path, path) do
        RecoverySecret.stub(:app_node_id, "original-node") do
          RecoverySecret.persist_user_passphrase!("persisted passphrase")
        end

        ENV.delete(RecoverySecret::PASSPHRASE_ENV)

        RecoverySecret.stub(:app_node_id, "new-node") do
          Rails.env.stub(:production?, true) do
            assert_raises(RecoverySecret::Missing) { RecoverySecret.required! }
          end
        end
      end
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end

  test "missing configured passphrase file falls back to environment passphrase" do
    with_recovery_env_cleared do
      missing_path = Rails.root.join("tmp/missing_recovery_secret_test_#{SecureRandom.hex(6)}.key")
      ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = missing_path.to_s
      ENV[RecoverySecret::PASSPHRASE_ENV] = "from env fallback"

      Rails.env.stub(:production?, true) do
        assert_equal "from env fallback", RecoverySecret.required!
      end
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
