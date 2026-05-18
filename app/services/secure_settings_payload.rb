require "openssl"

class SecureSettingsPayload
  PURPOSE = "idea-foundry-secure-settings-payload-v1".freeze

  class << self
    def encrypt(payload)
      return nil if payload.nil?

      encryptor.encrypt_and_sign(payload, purpose: PURPOSE)
    end

    def decrypt(ciphertext)
      return nil if ciphertext.blank?

      encryptor.decrypt_and_verify(ciphertext, purpose: PURPOSE)
    end

    def configured_external_key?
      RecoverySecret.present?
    end

    private

    def encryptor
      ActiveSupport::MessageEncryptor.new(secret_key, cipher: "aes-256-gcm", serializer: JSON)
    end

    def secret_key
      RecoverySecret.settings_key(key_length)
    end

    def key_length
      ActiveSupport::MessageEncryptor.key_len("aes-256-gcm")
    end
  end
end
