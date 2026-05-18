require "test_helper"

class SqlcipherDatabaseMigratorTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/sqlcipher_migrator_test")
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    @database_path = @root.join("production.sqlite3")
    @backup_dir = @root.join("backups")

    db = SQLite3::Database.new(@database_path.to_s)
    db.execute("CREATE TABLE ideas (id integer primary key, title text)")
    db.execute("INSERT INTO ideas (title) VALUES (?)", ["Encrypted from app"])
    db.close
  end

  teardown do
    FileUtils.rm_rf(@root) if @root&.exist?
  end

  test "migrates a plaintext SQLite database to SQLCipher with backup" do
    result = SqlcipherDatabaseMigrator.new(
      key_hex: RecoverySecret.sqlcipher_key_hex,
      backup_dir: @backup_dir,
      timestamp: "20260518123045"
    ).migrate!(@database_path)

    assert_equal :encrypted, result.status
    assert_equal @database_path.to_s, result.path
    assert_equal @backup_dir.join("production.sqlite3.20260518123045.plaintext").to_s, result.backup_path
    assert_equal "SQLite format 3\0", File.binread(result.backup_path, 16)
    refute_equal "SQLite format 3\0", File.binread(@database_path, 16)

    encrypted = SQLite3::Database.new(@database_path.to_s)
    encrypted.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
    assert_equal "Encrypted from app", encrypted.get_first_value("SELECT title FROM ideas")
  ensure
    encrypted&.close
  end
end
