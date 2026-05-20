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

    if plaintext_sqlite_database?(path)
      Rails.logger.warn("SQLCipher database at #{path} is plaintext; open /settings/security to encrypt it from the UI.")
      return
    end

    if encrypted_sqlcipher_database?(path) && !RecoverySecret.present?
      raise RecoverySecret::Missing, "Enter the recovery passphrase in /settings/security before opening encrypted data"
    end

    return unless path.blank? || File.exist?(path) || RecoverySecret.present?

    unless sqlcipher_available?
      raise "SQLite3 gem is not linked with SQLCipher. Rebuild the image/gem with libsqlcipher and --with-sqlcipher before opening encrypted databases."
    end

    @raw_connection.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
    @raw_connection.execute("PRAGMA cipher_memory_security = ON") rescue nil
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
