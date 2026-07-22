# SQLCipher must receive its key before Rails runs any other SQLite PRAGMAs
# or schema queries. Rails' sqlite3 adapter does not have a first-class key
# option, so production connections marked with `sqlcipher: true` are keyed here.
module IdeaFoundrySqlcipherConnectionKey
  private

  def configure_connection
    apply_sqlcipher_key! if @config[:sqlcipher]
    super
  end

  def apply_sqlcipher_key!
    path = database_path
    encrypted_database = encrypted_sqlcipher_database?(path)

    # SQLite opens a missing database by creating a zero-byte file before this
    # hook runs. Treat that file as an uninitialized database so db:prepare can
    # create the first-run plaintext schema. Encryption remains an explicit
    # action in Settings; there is no recovery secret to request yet.
    if empty_sqlite_database?(path)
      Rails.logger.info("SQLCipher database at #{path} is empty; allowing first-run database preparation before UI encryption is enabled.")
      return
    end

    if plaintext_sqlite_database?(path)
      Rails.logger.warn("SQLCipher database at #{path} is plaintext; open /settings/security to encrypt it from the UI.")
      return
    end

    if encrypted_database && !RecoverySecret.present?
      raise RecoverySecret::Missing, "Enter the recovery passphrase in /settings/security before opening encrypted data"
    end

    return unless path.blank? || File.exist?(path) || RecoverySecret.present?

    unless sqlcipher_available?
      raise "SQLite3 gem is not linked with SQLCipher. Rebuild the image/gem with libsqlcipher and --with-sqlcipher before opening encrypted databases."
    end

    Rails.logger.silence do
      @raw_connection.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
      begin
      @raw_connection.execute("PRAGMA cipher_memory_security = ON")
    rescue => e
      Rails.logger.warn("[SQLCipher] cipher_memory_security not set: #{e.message}")
    end
    end

    verify_sqlcipher_database_unlock! if encrypted_database
  rescue SQLite3::NotADatabaseException
    raise RecoverySecret::Missing, "Enter the recovery passphrase in /settings/security before opening encrypted data"
  end

  def verify_sqlcipher_database_unlock!
    @raw_connection.get_first_value("SELECT count(*) FROM sqlite_master")
  end

  def sqlcipher_available?
    version = @raw_connection.get_first_value("PRAGMA cipher_version") rescue nil
    return true if version.present?

    ::SQLite3.respond_to?(:sqlcipher?) && ::SQLite3.sqlcipher?
  end

  def plaintext_sqlite_database?(path = database_path)
    path.present? && File.file?(path) && File.binread(path, 16) == "SQLite format 3\0"
  rescue SystemCallError
    false
  end

  def empty_sqlite_database?(path = database_path)
    path.present? && File.file?(path) && File.zero?(path)
  rescue SystemCallError
    false
  end

  def encrypted_sqlcipher_database?(path = database_path)
    path.present? && File.file?(path) && File.size(path).positive? && !plaintext_sqlite_database?(path)
  rescue SystemCallError
    false
  end

  def database_path
    database = @config[:database]
    return if database.blank? || database == ":memory:"

    path = Pathname.new(database.to_s)
    path.absolute? ? path.to_s : Rails.root.join(path).to_s
  end
end

if defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(IdeaFoundrySqlcipherConnectionKey)
else
  ActiveSupport.on_load(:active_record_sqlite3adapter) do
    prepend IdeaFoundrySqlcipherConnectionKey
  end
end

# Migrate co-located recovery_passphrase.key → OS keychain on startup.
ActiveSupport.on_load(:after_initialize) do
  RecoverySecret.migrate_legacy_credential!
end
