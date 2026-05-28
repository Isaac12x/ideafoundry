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

  # N=2^14 was used to encrypt all existing databases — do not change without
  # running a PRAGMA rekey migration. N=2^17 (OWASP 2023) applies to new DBs.
  SCRYPT_N = 2**14
  SCRYPT_N_DEFAULT = 2**17
  SCRYPT_R = 8
  SCRYPT_P = 1
  PBKDF2_ITERATIONS = 210_000
  THREAD_SECRET_KEY = :idea_foundry_recovery_passphrase

  # In-process cache for the OS keychain read (one subprocess per process lifetime).
  # Env/file sources are always read dynamically so test env-var overrides work.
  @keychain_cache = nil
  @keychain_mutex = Mutex.new

  class Missing < KeyError; end

  class << self
    def with(passphrase, override_configured: false)
      previous = Thread.current[THREAD_SECRET_KEY]
      previous_override = Thread.current[override_thread_secret_key]
      Thread.current[THREAD_SECRET_KEY] = passphrase.presence
      Thread.current[override_thread_secret_key] = override_configured
      yield
    ensure
      Thread.current[THREAD_SECRET_KEY] = previous
      Thread.current[override_thread_secret_key] = previous_override
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

    def sqlcipher_key_hex_for(passphrase, n: nil)
      derive_key(SQLCIPHER_SALT, value: passphrase, n: n).unpack1("H*")
    end

    def rekey_needed?
      (read_configured_kdf_n || SCRYPT_N) < SCRYPT_N_DEFAULT
    end

    def rekey!(passphrase, env: Rails.env)
      current_n = read_configured_kdf_n || SCRYPT_N
      return false unless current_n < SCRYPT_N_DEFAULT

      old_key_hex = sqlcipher_key_hex_for(passphrase, n: current_n)
      new_key_hex = sqlcipher_key_hex_for(passphrase, n: SCRYPT_N_DEFAULT)

      SqlcipherDatabaseMigrator.rekey_configured!(env: env, old_key_hex: old_key_hex, new_key_hex: new_key_hex)
      store_credential!(passphrase, kdf_n: SCRYPT_N_DEFAULT)
      true
    end

    def settings_key(length)
      derive_key(SETTINGS_SALT, length: length)
    end

    # Returns the path used for file-based credential storage.
    # Warns (in production) when PASSPHRASE_FILE_ENV points inside the app directory,
    # since that co-locates the key with the database it protects.
    def user_passphrase_file_path
      configured_path = ENV[PASSPHRASE_FILE_ENV].presence
      if configured_path.present?
        path = Pathname.new(configured_path)
        if Rails.env.production? && path.expand_path.to_s.start_with?(Rails.root.expand_path.to_s)
          Rails.logger.warn "[RecoverySecret] Recovery passphrase file is inside the application " \
                            "directory (#{path}). Move it outside #{Rails.root} to separate the key " \
                            "from the database it protects. Set #{PASSPHRASE_FILE_ENV} accordingly."
        end
        return path
      end

      RecoveryKeychain.fallback_path
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
      kdf_n = read_configured_kdf_n || SCRYPT_N_DEFAULT
      store_credential!(passphrase, kdf_n: kdf_n)
    end

    # One-time startup migration: moves old co-located storage/recovery_passphrase.key
    # into the OS keychain and deletes the insecure copy.
    def migrate_legacy_credential!
      return if Rails.env.test?

      legacy_path = Rails.root.join("storage", "recovery_passphrase.key")
      return unless legacy_path.file?

      cred = read_credential_file(legacy_path)
      return unless cred&.fetch(:passphrase, nil).present?

      RecoveryKeychain.store(
        cred[:passphrase],
        app_node_id: app_node_id,
        kdf_params: { n: cred.fetch(:kdf_n, SCRYPT_N), r: SCRYPT_R, p: SCRYPT_P }
      )
      FileUtils.rm_f(legacy_path)
      Rails.logger.info "[RecoverySecret] Migrated recovery passphrase from storage/ to OS keychain"
      invalidate_keychain_cache!
    rescue => e
      Rails.logger.warn "[RecoverySecret] Legacy credential migration failed: #{e.class}: #{e.message}"
    end

    private

    # ── Keychain cache ──────────────────────────────────────────────────────
    # Only the OS keychain read is cached (it spawns a subprocess).
    # Env vars and file reads happen dynamically so test overrides work.

    def keychain_credential
      return nil if Rails.env.test?
      @keychain_mutex.synchronize { @keychain_cache ||= RecoveryKeychain.retrieve(app_node_id: app_node_id) }
    end

    def invalidate_keychain_cache!
      @keychain_mutex.synchronize { @keychain_cache = nil }
    end

    # ── Secret resolution ───────────────────────────────────────────────────

    def raw_secret
      request_secret = Thread.current[THREAD_SECRET_KEY].presence
      return request_secret if request_secret.present? && Thread.current[override_thread_secret_key]

      configured = configured_secret
      return configured if configured.present?

      request_secret
    end

    def override_thread_secret_key
      :idea_foundry_recovery_passphrase_overrides_configured_secret
    end

    # Priority: OS keychain → PASSPHRASE_FILE_ENV file → env vars → legacy file.
    def configured_secret
      cred = keychain_credential
      return cred[:passphrase] if cred&.fetch(:passphrase, nil).present?

      configured_file_path = ENV[PASSPHRASE_FILE_ENV].presence
      if configured_file_path.present?
        file_cred = read_credential_file(configured_file_path)
        return file_cred[:passphrase] if file_cred&.fetch(:passphrase, nil).present?
      end

      env_pass = ENV[PASSPHRASE_ENV].presence || ENV[LEGACY_ENV].presence || ENV["SQLCIPHER"].presence
      return env_pass if env_pass.present?

      legacy_path = Rails.root.join("storage", "recovery_passphrase.key")
      if legacy_path.file?
        legacy_cred = read_credential_file(legacy_path)
        return legacy_cred[:passphrase] if legacy_cred&.fetch(:passphrase, nil).present?
      end

      nil
    end

    # ── KDF params ──────────────────────────────────────────────────────────

    def read_configured_kdf_n
      cred = keychain_credential
      return cred[:kdf_n] if cred&.fetch(:kdf_n, nil).present?

      configured_file_path = ENV[PASSPHRASE_FILE_ENV].presence
      if configured_file_path.present?
        file_cred = read_credential_file(configured_file_path)
        return file_cred[:kdf_n] if file_cred&.fetch(:kdf_n, nil).present?
      end

      nil
    end

    # ── Credential persistence ───────────────────────────────────────────────

    def store_credential!(passphrase, kdf_n:)
      kdf_params = { n: kdf_n, r: SCRYPT_R, p: SCRYPT_P }

      # Primary: OS keychain (skipped in test to avoid polluting the real keychain)
      unless Rails.env.test?
        RecoveryKeychain.store(passphrase, app_node_id: app_node_id, kdf_params: kdf_params)
        invalidate_keychain_cache!
      end

      # File fallback: always written for Docker, backward compat, and test isolation
      path = write_passphrase_file!(passphrase, kdf_params)
      ENV[PASSPHRASE_FILE_ENV] = path.to_s
      path
    end

    # ── File I/O ────────────────────────────────────────────────────────────

    def write_passphrase_file!(passphrase, kdf_params)
      path = user_passphrase_file_path
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.generate({
        "version" => 2,
        "app_node_id" => app_node_id,
        "passphrase" => passphrase.to_s,
        "kdf_n" => kdf_params[:n],
        "kdf_r" => kdf_params[:r],
        "kdf_p" => kdf_params[:p]
      }))
      File.chmod(0o600, path)
      path
    end

    def read_credential_file(path)
      path = Pathname.new(path.to_s)
      return unless path.file?

      decode_persisted_credential(File.read(path))
    end

    def decode_persisted_credential(contents)
      stripped = contents.to_s.strip
      return if stripped.blank?

      parsed = JSON.parse(stripped)

      unless parsed.is_a?(Hash) && parsed.key?("passphrase")
        return { passphrase: stripped.presence, kdf_n: SCRYPT_N }
      end

      return unless parsed["app_node_id"].to_s == app_node_id

      passphrase = parsed["passphrase"].to_s.presence
      return unless passphrase

      {
        passphrase: passphrase,
        kdf_n: parsed["kdf_n"]&.to_i || SCRYPT_N,
        kdf_r: parsed["kdf_r"]&.to_i || SCRYPT_R,
        kdf_p: parsed["kdf_p"]&.to_i || SCRYPT_P
      }
    rescue JSON::ParserError
      { passphrase: stripped.presence, kdf_n: SCRYPT_N }
    end

    # ── Key derivation ──────────────────────────────────────────────────────

    def derive_key(salt, length: 32, value: self.value, n: nil)
      kdf_n = n || read_configured_kdf_n || SCRYPT_N
      key_material = decode_key_material(value)
      OpenSSL::KDF.scrypt(key_material, salt: salt, N: kdf_n, r: SCRYPT_R, p: SCRYPT_P, length: length)
    rescue NoMethodError
      key_material = decode_key_material(value)
      OpenSSL::PKCS5.pbkdf2_hmac(key_material, salt, PBKDF2_ITERATIONS, length, OpenSSL::Digest::SHA256.new)
    end

    def decode_key_material(value)
      Base64.strict_decode64(value)
    rescue ArgumentError
      value
    end
  end
end
