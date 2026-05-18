require "base64"
require "openssl"

class RecoverySecret
  PASSPHRASE_ENV = "IDEA_FOUNDRY_RECOVERY_PASSPHRASE".freeze
  PASSPHRASE_FILE_ENV = "IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE".freeze
  LEGACY_ENV = "IDEA_FOUNDRY_DATA_ENCRYPTION_KEY".freeze
  SQLCIPHER_SALT = "idea-foundry:sqlcipher-database-key:v1".freeze
  SETTINGS_SALT = "idea-foundry:secure-settings-key:v1".freeze
  SCRYPT_N = 2**14
  SCRYPT_R = 8
  SCRYPT_P = 1
  PBKDF2_ITERATIONS = 210_000

  class Missing < KeyError; end

  class << self
    def present?
      raw_secret.present?
    end

    def required!
      secret = raw_secret.presence
      if secret.blank?
        raise Missing, "Set #{PASSPHRASE_ENV} or #{PASSPHRASE_FILE_ENV} to the user-held recovery passphrase before opening encrypted data"
      end

      secret
    end

    def value
      configured = raw_secret.presence
      return configured if configured.present?

      if Rails.env.production?
        required!
      else
        "idea-foundry-development-test-recovery-secret"
      end
    end

    def sqlcipher_key_hex
      derive_key(SQLCIPHER_SALT).unpack1("H*")
    end

    def settings_key(length)
      derive_key(SETTINGS_SALT, length: length)
    end

    private

    def raw_secret
      file_path = ENV[PASSPHRASE_FILE_ENV].presence
      return File.read(file_path).strip if file_path.present?

      ENV[PASSPHRASE_ENV].presence || ENV[LEGACY_ENV].presence
    end

    def derive_key(salt, length: 32)
      key_material = decode_key_material(value)
      OpenSSL::KDF.scrypt(key_material, salt: salt, N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P, length: length)
    rescue NoMethodError
      OpenSSL::PKCS5.pbkdf2_hmac(key_material, salt, PBKDF2_ITERATIONS, length, OpenSSL::Digest::SHA256.new)
    end

    def decode_key_material(value)
      Base64.strict_decode64(value)
    rescue ArgumentError
      value
    end
  end
end
