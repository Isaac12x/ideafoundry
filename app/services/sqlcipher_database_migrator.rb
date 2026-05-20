require "fileutils"
require "pathname"
require "sqlite3"

class SqlcipherDatabaseMigrator
  SQLITE_HEADER = "SQLite format 3\0".b.freeze
  SIDECAR_SUFFIXES = ["-wal", "-shm"].freeze

  Result = Struct.new(:path, :status, :backup_path, :error, keyword_init: true)

  class Error < StandardError; end

  def self.configured_database_paths(env:)
    ActiveRecord::Base.configurations.configs_for(env_name: env).filter_map do |config|
      configuration = config.configuration_hash
      next unless configuration[:sqlcipher]

      resolve_database_path(configuration[:database])
    end.uniq
  end

  def self.locked_database_paths_without_recovery_secret(env:)
    return [] if RecoverySecret.present?

    configured_database_paths(env: env).select do |path|
      path = Pathname.new(path.to_s)
      path.file? && path.size.positive? && !plaintext_sqlite_database?(path)
    end
  end

  def self.resolve_database_path(database)
    return if database.blank? || database == ":memory:"

    path = Pathname.new(database.to_s)
    path.absolute? ? path.to_s : Rails.root.join(path).to_s
  end

  def self.plaintext_sqlite_database?(path)
    File.file?(path) && File.binread(path, SQLITE_HEADER.bytesize) == SQLITE_HEADER
  end

  def initialize(key_hex:, backup_dir: nil, timestamp: Time.now.utc.strftime("%Y%m%d%H%M%S"))
    @key_hex = key_hex.to_s
    @backup_dir = Pathname.new((backup_dir.presence || default_backup_dir).to_s)
    @timestamp = timestamp

    validate_key!
  end

  def migrate_configured!(env:)
    self.class.configured_database_paths(env: env).map { |path| migrate!(path) }
  end

  def configured_statuses(env:)
    self.class.configured_database_paths(env: env).map { |path| status_for(path) }
  end

  def status_for(database)
    path = Pathname.new(database.to_s)
    path = Rails.root.join(path) unless path.absolute?

    return Result.new(path: path.to_s, status: :missing) unless path.exist?
    return Result.new(path: path.to_s, status: :plaintext) if plaintext_sqlite_database?(path)

    ensure_sqlcipher_available!
    verify_encrypted_database!(path)
    Result.new(path: path.to_s, status: :encrypted)
  rescue Error, SQLite3::SQLException, SQLite3::NotADatabaseException, SQLite3::IOException => e
    Result.new(path: path.to_s, status: :unreadable, error: e.message)
  end

  def migrate!(database)
    ensure_sqlcipher_available!

    path = Pathname.new(database.to_s)
    path = Rails.root.join(path) unless path.absolute?

    return Result.new(path: path.to_s, status: :missing) unless path.exist?
    return Result.new(path: path.to_s, status: :already_encrypted) if encrypted_database?(path)

    unless plaintext_sqlite_database?(path)
      raise Error, "#{path} is neither plaintext SQLite nor an openable SQLCipher database"
    end

    temp_path = temporary_path(path)
    export_plaintext_to_sqlcipher!(path, temp_path)
    verify_encrypted_database!(temp_path)

    backup_path = backup_plaintext_database!(path)
    replace_database!(path, temp_path)

    Result.new(path: path.to_s, status: :encrypted, backup_path: backup_path.to_s)
  ensure
    FileUtils.rm_f(temp_path) if temp_path&.exist?
  end

  private

  def default_backup_dir
    Rails.root.dirname.join("#{Rails.root.basename}-sqlcipher-backups")
  end

  def validate_key!
    return if @key_hex.match?(/\A[0-9a-f]{64}\z/i)

    raise Error, "SQLCipher key must be a 64-character hex string"
  end

  def ensure_sqlcipher_available!
    db = SQLite3::Database.new(":memory:")
    version = db.get_first_value("PRAGMA cipher_version") rescue nil
    return if version.present?

    raise Error, "SQLite3 gem is not linked with SQLCipher. Run bundle install with the repository Bundler config."
  ensure
    db&.close
  end

  def encrypted_database?(path)
    verify_encrypted_database!(path)
    true
  rescue SQLite3::SQLException, SQLite3::NotADatabaseException, SQLite3::IOException
    false
  end

  def verify_encrypted_database!(path)
    db = SQLite3::Database.new(path.to_s)
    db.execute(%(PRAGMA key = #{key_literal}))
    db.get_first_value("SELECT count(*) FROM sqlite_master")

    integrity = db.get_first_value("PRAGMA integrity_check")
    raise Error, "SQLCipher integrity check failed for #{path}: #{integrity}" unless integrity == "ok"
  ensure
    db&.close
  end

  def plaintext_sqlite_database?(path)
    self.class.plaintext_sqlite_database?(path)
  end

  def export_plaintext_to_sqlcipher!(source_path, encrypted_path)
    FileUtils.rm_f(encrypted_path)

    source = SQLite3::Database.new(source_path.to_s)
    source.busy_timeout = 10_000
    source.execute("PRAGMA wal_checkpoint(TRUNCATE)") rescue nil
    source.execute("ATTACH DATABASE #{sql_string(encrypted_path.to_s)} AS encrypted KEY #{key_literal}")
    source.execute("SELECT sqlcipher_export('encrypted')")
    source.execute("DETACH DATABASE encrypted")
  ensure
    source&.close
  end

  def backup_plaintext_database!(path)
    FileUtils.mkdir_p(@backup_dir)

    backup_path = @backup_dir.join("#{path.basename}.#{@timestamp}.plaintext")
    raise Error, "Backup already exists: #{backup_path}" if backup_path.exist?

    FileUtils.cp(path, backup_path, preserve: true)
    sidecar_paths(path).each do |sidecar|
      next unless sidecar.exist?

      FileUtils.cp(sidecar, @backup_dir.join("#{sidecar.basename}.#{@timestamp}.plaintext"), preserve: true)
    end

    backup_path
  end

  def replace_database!(path, encrypted_path)
    mode = File.stat(path).mode & 0o7777
    sidecar_paths(path).each { |sidecar| FileUtils.rm_f(sidecar) }
    File.rename(encrypted_path, path)
    File.chmod(mode, path)
  end

  def temporary_path(path)
    path.dirname.join(".#{path.basename}.#{@timestamp}.sqlcipher")
  end

  def sidecar_paths(path)
    SIDECAR_SUFFIXES.map { |suffix| Pathname.new("#{path}#{suffix}") }
  end

  def sql_string(value)
    "'#{value.to_s.gsub("'", "''")}'"
  end

  def key_literal
    %("x'#{@key_hex}'")
  end
end
