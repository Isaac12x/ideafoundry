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
    unless sqlcipher_available?
      raise "SQLite3 gem is not linked with SQLCipher. Rebuild the image/gem with libsqlcipher and --with-sqlcipher before opening encrypted databases."
    end

    @raw_connection.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
    @raw_connection.execute("PRAGMA cipher_memory_security = ON") rescue nil
  end

  def sqlcipher_available?
    return ::SQLite3.sqlcipher? if ::SQLite3.respond_to?(:sqlcipher?)

    version = @raw_connection.get_first_value("PRAGMA cipher_version") rescue nil
    version.present?
  end
end

if defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(IdeaFoundrySqlcipherConnectionKey)
else
  ActiveSupport.on_load(:active_record_sqlite3adapter) do
    prepend IdeaFoundrySqlcipherConnectionKey
  end
end
