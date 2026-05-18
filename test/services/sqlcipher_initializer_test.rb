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
  end

  FakeConnection = Struct.new(:cipher_version) do
    def get_first_value(sql)
      raise ArgumentError, sql unless sql == "PRAGMA cipher_version"

      cipher_version
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
end
