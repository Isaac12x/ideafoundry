class EncryptUserSecuritySettings < ActiveRecord::Migration[8.0]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
    serialize :settings, coder: JSON
  end

  PROTECTED_SETTINGS = {
    "typing_lock" => "fingerprint",
    "authenticator_app" => "secret",
    "voice_id" => "fingerprint"
  }.freeze

  def up
    migrate_security_settings(encrypt: true)
  end

  def down
    migrate_security_settings(encrypt: false)
  end

  private

  def migrate_security_settings(encrypt:)
    unless RecoverySecret.present?
      if encrypt
        say "Skipping security settings encryption until a recovery passphrase is entered in /settings/security", true
        return
      end

      RecoverySecret.required!
    end

    MigrationUser.find_each do |user|
      settings = user.settings || {}
      changed = false

      PROTECTED_SETTINGS.each do |section, key|
        bucket = settings[section]
        next unless bucket.is_a?(Hash)

        ciphertext_key = "#{key}_ciphertext"

        if encrypt
          next if bucket[key].blank? || bucket[ciphertext_key].present?

          bucket[ciphertext_key] = SecureSettingsPayload.encrypt(bucket[key])
          bucket.delete(key)
          changed = true
        else
          next if bucket[ciphertext_key].blank? || bucket[key].present?

          bucket[key] = SecureSettingsPayload.decrypt(bucket[ciphertext_key])
          bucket.delete(ciphertext_key)
          changed = true
        end
      end

      user.update_columns(settings: settings) if changed
    end
  end
end
