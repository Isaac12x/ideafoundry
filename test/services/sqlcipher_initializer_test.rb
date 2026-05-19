require "test_helper"

class SqlcipherInitializerTest < ActiveSupport::TestCase
  class Probe
    include IdeaFoundrySqlcipherConnectionKey

    def initialize(raw_connection, database: nil)
      @raw_connection = raw_connection
      @config = { database: database }
    end

    def available?
      send(:sqlcipher_available?)
    end

    def plaintext?
      send(:plaintext_sqlite_database?)
    end

    def apply_key!
      send(:apply_sqlcipher_key!)
    end
  end

  FakeConnection = Struct.new(:cipher_version, :executed_sql) do
    def initialize(cipher_version)
      super(cipher_version, [])
    end

    def get_first_value(sql)
      raise ArgumentError, sql unless sql == "PRAGMA cipher_version"

      cipher_version
    end

    def execute(sql)
      executed_sql << sql
    end
  end

  test "SQLCipher availability trusts the live cipher version pragma" do
    connection = FakeConnection.new("4.14.0 community")

    SQLite3.stub(:sqlcipher?, false) do
      assert Probe.new(connection).available?
    end
  end

  test "SQLCipher availability falls back to sqlite3 gem marker" do
    connection = FakeConnection.new(nil)

    SQLite3.stub(:sqlcipher?, true) do
      assert Probe.new(connection).available?
    end
  end

  test "plaintext SQLite databases are detected before applying SQLCipher key" do
    path = Rails.root.join("tmp/plaintext_sqlite_initializer_test.sqlite3")
    File.binwrite(path, "SQLite format 3\0")

    assert Probe.new(FakeConnection.new("4.14.0 community"), database: path.to_s).plaintext?
  ensure
    File.delete(path) if path&.exist?
  end

  test "plaintext SQLCipher databases stay open so security settings can encrypt them" do
    path = Rails.root.join("tmp/plaintext_sqlite_initializer_test.sqlite3")
    File.binwrite(path, "SQLite format 3\0")
    connection = FakeConnection.new(nil)

    SQLite3.stub(:sqlcipher?, false) do
      assert_nothing_raised do
        Probe.new(connection, database: path.to_s).apply_key!
      end
    end

    assert_empty connection.executed_sql
  ensure
    File.delete(path) if path&.exist?
  end

  test "encrypted SQLCipher database raises recovery prompt before Rails schema queries when no passphrase is loaded" do
    path = Rails.root.join("tmp/encrypted_sqlcipher_initializer_test.sqlite3")
    File.binwrite(path, "not a sqlite header")
    connection = FakeConnection.new("4.14.0 community")

    RecoverySecret.stub(:present?, false) do
      error = assert_raises(RecoverySecret::Missing) do
        Probe.new(connection, database: path.to_s).apply_key!
      end

      assert_equal "Enter the recovery passphrase in /settings/security before opening encrypted data", error.message
    end

    assert_empty connection.executed_sql
  ensure
    File.delete(path) if path&.exist?
  end

  test "missing SQLCipher databases are allowed to be created before UI encryption is enabled" do
    path = Rails.root.join("tmp/missing_sqlcipher_initializer_test.sqlite3")
    File.delete(path) if path.exist?
    connection = FakeConnection.new(nil)

    RecoverySecret.stub(:present?, false) do
      SQLite3.stub(:sqlcipher?, false) do
        assert_nothing_raised do
          Probe.new(connection, database: path.to_s).apply_key!
        end
      end
    end

    assert_empty connection.executed_sql
  ensure
    File.delete(path) if path&.exist?
  end
end
