require "fileutils"
require "open3"
require "pathname"
require "sqlite3"

class SqlcipherDatabaseMigrator
  SQLITE_HEADER = "SQLite format 3\0".b.freeze
  SIDECAR_SUFFIXES = [ "-wal", "-shm" ].freeze
  LOCK_MUTEX = Mutex.new
  RETAINED_LOCKS = []

  Result = Struct.new(:path, :status, :error, keyword_init: true)

  class Error < StandardError; end

  def self.configured_database_paths(env:)
    ActiveRecord::Base.configurations.configs_for(env_name: env).filter_map do |config|
      configuration = config.configuration_hash
      next unless configuration[:sqlcipher]

      resolve_database_path(configuration[:database])
    end.uniq
  end

  def self.locked_database_paths_without_recovery_secret(env:)
    configured_database_paths(env: env).select do |path|
      locked_database_path_for_startup?(path)
    end
  end

  def self.locked_database_path_for_startup?(path)
    path = Pathname.new(path.to_s)
    # A first run has no database file (or SQLite has only touched an empty
    # placeholder). There is no encrypted data to recover in either case.
    return false unless path.file? && path.size.positive?
    return false if plaintext_sqlite_database?(path)
    return true unless RecoverySecret.present?

    return false if accessible_via_active_record?(path)

    !encrypted_database_openable_with_current_key?(path)
  rescue SystemCallError
    false
  end

  def self.accessible_via_active_record?(path)
    resolved = resolve_database_path(path)
    return false if resolved.blank?

    config = active_record_config_for_path(resolved)
    return false unless config

    with_active_record_connection(config) do |connection|
      connection.select_value("SELECT 1") == 1
    end
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, SQLite3::Exception
    false
  end

  def self.active_record_config_for_path(resolved_path)
    target = Pathname.new(resolved_path.to_s).cleanpath.to_s
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).find do |config|
      next unless config.configuration_hash[:sqlcipher]

      Pathname.new(resolve_database_path(config.configuration_hash[:database]).to_s).cleanpath.to_s == target
    end
  end

  def self.with_active_record_connection(config)
    if config.name == "primary"
      yield ActiveRecord::Base.connection
    else
      ActiveRecord::Base.connected_to(role: :writing, shard: config.name.to_sym) do
        yield ActiveRecord::Base.connection
      end
    end
  end

  def self.encrypted_database_openable_with_current_key?(path)
    new(key_hex: RecoverySecret.sqlcipher_key_hex).send(:verify_encrypted_database!, Pathname.new(path.to_s))
    true
  rescue RecoverySecret::Missing, Error, SQLite3::SQLException, SQLite3::NotADatabaseException, SQLite3::IOException
    false
  end

  def self.resolve_database_path(database)
    return if database.blank? || database == ":memory:"

    path = Pathname.new(database.to_s)
    path.absolute? ? path.to_s : Rails.root.join(path).to_s
  end

  def self.rekey_configured!(env:, old_key_hex:, new_key_hex:)
    paths = configured_database_paths(env: env)
    ensure_no_other_openers!(paths) # all or nothing: never rekey some files and then refuse the rest
    paths.each { |path| new(key_hex: old_key_hex).rekey!(path, new_key_hex: new_key_hex) }
  end

  # Concurrency design. A re-encrypt replaces the file (new inode); a process still holding the old inode would keep
  # writing into the unlinked file and those writes would be lost. So:
  #  1. Refuse unless no OTHER process has the database (or its -wal/-shm) open. lsof proves it, and a missing lsof
  #     refuses too. Run it offline: stop puma + bin/jobs, then `bin/rails db:encrypt_sqlite`.
  #  2. Take the write lock (BEGIN IMMEDIATE, busy timeout) before exporting and hold it through the rename.
  #  3. Never release it: the lock connection is retained until this process exits, so even a stale handle inside
  #     this process gets SQLITE_BUSY instead of writing to the old inode.
  def self.ensure_no_other_openers!(paths)
    files = Array(paths).flat_map { |p| [ p.to_s, "#{p}-wal", "#{p}-shm" ] }
    out, _err, status = Open3.capture3("lsof", "-t", "--", *files)
    raise Error, "lsof failed (exit #{status.exitstatus}); cannot prove the database is not in use" if status.exitstatus > 1

    pids = out.split.map(&:to_i).uniq - [ Process.pid ]
    return if pids.empty?

    raise Error, "Database is in use by process #{pids.to_sentence}. Stop the app (puma and bin/jobs) and run `bin/rails db:encrypt_sqlite` offline."
  rescue Errno::ENOENT
    raise Error, "lsof is required to prove no other process has the database open; install it and retry"
  end

  def self.retain_lock(connection)
    LOCK_MUTEX.synchronize { RETAINED_LOCKS << connection }
  end

  def self.release_retained_locks! # tests only; production holds them until the process exits
    LOCK_MUTEX.synchronize { RETAINED_LOCKS.shift.close until RETAINED_LOCKS.empty? }
  end

  def self.plaintext_sqlite_database?(path)
    File.file?(path) && File.binread(path, SQLITE_HEADER.bytesize) == SQLITE_HEADER
  end

  def initialize(key_hex:, timestamp: Time.now.utc.strftime("%Y%m%d%H%M%S"))
    @key_hex = key_hex.to_s
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

    reencrypt!(path, from_key_hex: nil, to_key_hex: @key_hex)
    Result.new(path: path.to_s, status: :encrypted)
  end

  # Same safe path as migrate!: export under the write lock, verify, atomic rename.
  def rekey!(database, new_key_hex:)
    raise Error, "New key must be a 64-character hex string" unless new_key_hex.to_s.match?(/\A[0-9a-f]{64}\z/i)

    path = Pathname.new(database.to_s)
    path = Rails.root.join(path) unless path.absolute?
    return unless path.exist? && !plaintext_sqlite_database?(path)

    reencrypt!(path, from_key_hex: @key_hex, to_key_hex: new_key_hex)
  end

  private

  # No plaintext copy is ever made. The original is untouched until the encrypted copy is fully written and
  # verified (integrity, per-table row counts), all under the write lock; only then does an atomic rename replace
  # it. Any failure before that leaves the original as it was (our own half-written temp file is discarded).
  def reencrypt!(path, from_key_hex:, to_key_hex:)
    self.class.ensure_no_other_openers!([ path ])
    temp_path = temporary_path(path)
    create_temp_exclusively!(temp_path)
    created = true

    checkpoint_wal!(path, from_key_hex)
    locker = open_database(path, from_key_hex)
    locker.execute("BEGIN IMMEDIATE") # blocks every other writer from here through the rename and beyond
    # Any frame written between the checkpoint and the lock would be lost with the sidecars if the rename failed.
    raise Error, "#{path} changed while the migration took its lock; nothing was modified, retry" if File.size?("#{path}-wal")

    export_encrypted_copy!(path, temp_path, from_key_hex, to_key_hex)
    verify_encrypted_database!(temp_path, to_key_hex)
    verify_same_row_counts!(locker, temp_path, to_key_hex)
    replace_database!(path, temp_path)
    created = false
    self.class.retain_lock(locker)
    locker = nil
  ensure
    locker&.close # rolls back the (empty) transaction; the original is untouched
    FileUtils.rm_f(temp_path) if created
  end

  # replace_database! drops the old -wal/-shm, so they must hold nothing: flush the WAL into the main file first.
  def checkpoint_wal!(path, key_hex)
    db = open_database(path, key_hex)
    busy, = db.get_first_row("PRAGMA wal_checkpoint(TRUNCATE)")
    raise Error, "#{path} has readers or writers that block flushing its WAL; nothing was modified" if busy.to_i != 0
  ensure
    db&.close
  end

  def create_temp_exclusively!(temp_path)
    File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { }
  rescue Errno::EEXIST
    raise Error, "Stale temporary file #{temp_path} exists; refusing to overwrite it. Remove it by hand if no migration is running."
  end

  def open_database(path, key_hex = nil)
    db = SQLite3::Database.new(path.to_s)
    db.busy_timeout = 10_000
    db.execute(%(PRAGMA key = #{key_literal(key_hex)})) if key_hex
    db
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

  def verify_encrypted_database!(path, key_hex = @key_hex)
    db = SQLite3::Database.new(path.to_s)
    db.execute(%(PRAGMA key = #{key_literal(key_hex)}))
    db.get_first_value("SELECT count(*) FROM sqlite_master")

    integrity = db.get_first_value("PRAGMA integrity_check")
    raise Error, "SQLCipher integrity check failed for #{path}: #{integrity}" unless integrity == "ok"
  ensure
    db&.close
  end

  def plaintext_sqlite_database?(path)
    self.class.plaintext_sqlite_database?(path)
  end

  # Reads through its own connection (WAL contents included); the caller's lock connection already blocks writers.
  def export_encrypted_copy!(source_path, encrypted_path, from_key_hex, to_key_hex)
    source = open_database(source_path, from_key_hex)
    source.execute("ATTACH DATABASE #{sql_string(encrypted_path.to_s)} AS encrypted KEY #{key_literal(to_key_hex)}")
    source.execute("SELECT sqlcipher_export('encrypted')")
    source.execute("DETACH DATABASE encrypted")
  ensure
    source&.close
  end

  def verify_same_row_counts!(source, encrypted_path, to_key_hex)
    encrypted = open_database(encrypted_path, to_key_hex)
    tables = source.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").flatten
    tables.each do |table|
      count_sql = %(SELECT count(*) FROM "#{table.gsub('"', '""')}")
      next if source.get_first_value(count_sql) == encrypted.get_first_value(count_sql)

      raise Error, "Row count mismatch in #{table}; refusing to replace the database"
    end
  ensure
    encrypted&.close
  end

  def replace_database!(path, encrypted_path)
    File.chmod(File.stat(path).mode & 0o7777, encrypted_path)
    # Stale -wal/-shm of the old file must not pair with the new one; our lock connection holds the old inode.
    sidecar_paths(path).each { |sidecar| FileUtils.rm_f(sidecar) }
    File.rename(encrypted_path, path)
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

  def key_literal(key_hex = @key_hex)
    %("x'#{key_hex}'")
  end
end
