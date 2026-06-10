require "test_helper"

class SqlcipherDatabaseMigratorTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/sqlcipher_migrator_test_#{Process.pid}_#{SecureRandom.hex(6)}")
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
    assert_nil result.backup_path, "Plaintext backup must be deleted after encryption"
    refute File.exist?(@backup_dir.join("production.sqlite3.20260518123045.plaintext")), "Plaintext backup file must not remain on disk"
    refute_equal "SQLite format 3\0", File.binread(@database_path, 16)

    encrypted = SQLite3::Database.new(@database_path.to_s)
    encrypted.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
    assert_equal "Encrypted from app", encrypted.get_first_value("SELECT title FROM ideas")
  ensure
    encrypted&.close
  end

  test "reports database encryption status before migrating from the UI" do
    migrator = SqlcipherDatabaseMigrator.new(
      key_hex: RecoverySecret.sqlcipher_key_hex,
      backup_dir: @backup_dir,
      timestamp: "20260518123045"
    )

    assert_equal :plaintext, migrator.status_for(@database_path).status
    assert_equal :missing, migrator.status_for(@root.join("missing.sqlite3")).status

    migrator.migrate!(@database_path)

    assert_equal :encrypted, migrator.status_for(@database_path).status
  end

  test "detects locked encrypted databases without requiring the recovery passphrase" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, false) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [@database_path.to_s, encrypted_path.to_s]) do
        assert_equal [encrypted_path.to_s], SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
      end
    end
  end

  test "locked database detection skips prepare when the loaded recovery passphrase cannot unlock the database" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, true) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [encrypted_path.to_s]) do
        SqlcipherDatabaseMigrator.stub(:encrypted_database_openable_with_current_key?, false) do
          assert_equal [encrypted_path.to_s], SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
        end
      end
    end
  end

  test "locked database detection allows prepare when the loaded recovery passphrase opens the database" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, true) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [encrypted_path.to_s]) do
        SqlcipherDatabaseMigrator.stub(:encrypted_database_openable_with_current_key?, true) do
          assert_empty SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
        end
      end
    end
  end
end
