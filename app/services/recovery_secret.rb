require "base64"
require "fileutils"
require "json"
require "openssl"
require "pathname"
require "securerandom"

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
  THREAD_SECRET_KEY = :idea_foundry_recovery_passphrase

  class Missing < KeyError; end

  class << self
    def with(passphrase)
      previous = Thread.current[THREAD_SECRET_KEY]
      Thread.current[THREAD_SECRET_KEY] = passphrase.presence
      yield
    ensure
      Thread.current[THREAD_SECRET_KEY] = previous
    end

    def present?
      raw_secret.present?
    end

    def required!
      secret = raw_secret.presence
      if secret.blank?
        raise Missing, "Enter the recovery passphrase in /settings/security before opening encrypted data"
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
      sqlcipher_key_hex_for(value)
    end

    def sqlcipher_key_hex_for(passphrase)
      derive_key(SQLCIPHER_SALT, value: passphrase).unpack1("H*")
    end

    def settings_key(length)
      derive_key(SETTINGS_SALT, length: length)
    end

    def user_passphrase_file_path
      configured_path = ENV[PASSPHRASE_FILE_ENV].presence
      return Pathname.new(configured_path) if configured_path.present?

      Rails.root.join("storage", "recovery_passphrase.key")
    end

    def app_node_id
      configured = ENV["IDEA_FOUNDRY_APP_NODE_ID"].presence
      return configured if configured.present?

      path = app_node_id_file_path
      if path.file?
        existing = File.read(path).strip.presence
        return existing if existing.present?
      end

      FileUtils.mkdir_p(path.dirname)
      SecureRandom.uuid.tap do |node_id|
        File.write(path, node_id)
        File.chmod(0o600, path)
      end
    end

    def app_node_id_file_path
      Rails.root.join("storage", "app_node_id")
    end

    def persist_user_passphrase!(passphrase)
      path = user_passphrase_file_path
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.generate({
        "version" => 1,
        "app_node_id" => app_node_id,
        "passphrase" => passphrase.to_s
      }))
      File.chmod(0o600, path)

      ENV[PASSPHRASE_FILE_ENV] = path.to_s

      path
    end

    private

    def raw_secret
      configured = configured_secret
      return configured if configured.present?

      Thread.current[THREAD_SECRET_KEY].presence
    end

    def configured_secret
      configured_file_path = ENV[PASSPHRASE_FILE_ENV].presence
      configured_file_secret = read_passphrase_file(configured_file_path) if configured_file_path.present?
      return configured_file_secret if configured_file_secret.present?

      env_secret = ENV[PASSPHRASE_ENV].presence || ENV[LEGACY_ENV].presence
      return env_secret if env_secret.present?

      read_passphrase_file(user_passphrase_file_path)
    end

    def read_passphrase_file(path)
      path = Pathname.new(path.to_s)
      return unless path.file?

      decode_persisted_passphrase(File.read(path))
    end

    def decode_persisted_passphrase(contents)
      stripped = contents.to_s.strip
      return if stripped.blank?

      parsed = JSON.parse(stripped)
      return stripped unless parsed.is_a?(Hash) && parsed.key?("passphrase")
      return unless parsed["app_node_id"].to_s == app_node_id

      parsed["passphrase"].to_s.presence
    rescue JSON::ParserError
      stripped.presence
    end

    def derive_key(salt, length: 32, value: self.value)
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
