require "test_helper"

class SqlcipherDatabaseMigratorTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/sqlcipher_migrator_test_#{Process.pid}_#{SecureRandom.hex(6)}")
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    @database_path = @root.join("production.sqlite3")

    db = SQLite3::Database.new(@database_path.to_s)
    db.execute("CREATE TABLE ideas (id integer primary key, title text)")
    db.execute("INSERT INTO ideas (title) VALUES (?)", [ "Encrypted from app" ])
    db.close
  end

  teardown do
    FileUtils.rm_rf(@root) if @root&.exist?
  end

  def migrator = SqlcipherDatabaseMigrator.new(key_hex: RecoverySecret.sqlcipher_key_hex, timestamp: "20260518123045")
  def files_under_root = Dir.glob(@root.join("**/*").to_s, File::FNM_DOTMATCH).select { |f| File.file?(f) }.map { |f| File.basename(f) }.sort

  test "migrates a plaintext SQLite database to SQLCipher without ever writing a plaintext copy" do
    result = migrator.migrate!(@database_path)

    assert_equal :encrypted, result.status
    assert_equal @database_path.to_s, result.path
    assert_equal [ "production.sqlite3" ], files_under_root, "no plaintext backup or temp file may exist"
    assert_not_respond_to result, :backup_path
    refute_equal "SQLite format 3\0", File.binread(@database_path, 16)

    encrypted = SQLite3::Database.new(@database_path.to_s)
    encrypted.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex}'"))
    assert_equal "Encrypted from app", encrypted.get_first_value("SELECT title FROM ideas")
  ensure
    encrypted&.close
  end

  test "the original stays untouched when verification of the encrypted copy fails" do
    before = File.binread(@database_path)
    m = migrator
    m.stub(:verify_encrypted_database!, ->(*) { raise SqlcipherDatabaseMigrator::Error, "boom" }) do
      assert_raises(SqlcipherDatabaseMigrator::Error) { m.migrate!(@database_path) }
    end

    assert_equal before, File.binread(@database_path)
    assert_equal [ "production.sqlite3" ], files_under_root
  end

  test "the original stays untouched when the final rename fails" do
    before = File.binread(@database_path)
    File.stub(:rename, ->(*) { raise Errno::EACCES }) do
      assert_raises(Errno::EACCES) { migrator.migrate!(@database_path) }
    end

    assert_equal before, File.binread(@database_path)
    assert_equal [ "production.sqlite3" ], files_under_root
  end

  test "reports database encryption status before migrating from the UI" do
    migrator = self.migrator

    assert_equal :plaintext, migrator.status_for(@database_path).status
    assert_equal :missing, migrator.status_for(@root.join("missing.sqlite3")).status

    migrator.migrate!(@database_path)

    assert_equal :encrypted, migrator.status_for(@database_path).status
  end

  test "detects locked encrypted databases without requiring the recovery passphrase" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, false) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @database_path.to_s, encrypted_path.to_s ]) do
        assert_equal [ encrypted_path.to_s ], SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
      end
    end
  end

  test "missing and empty databases do not require a recovery passphrase on first run" do
    missing_path = @root.join("missing.sqlite3")
    empty_path = @root.join("empty.sqlite3")
    FileUtils.touch(empty_path)

    RecoverySecret.stub(:present?, false) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ missing_path.to_s, empty_path.to_s ]) do
        assert_empty SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
      end
    end
  end

  test "a database removed during startup inspection is treated as missing" do
    disappearing_path = Object.new
    disappearing_path.define_singleton_method(:file?) { true }
    disappearing_path.define_singleton_method(:size) { raise Errno::ENOENT }

    Pathname.stub(:new, disappearing_path) do
      refute SqlcipherDatabaseMigrator.locked_database_path_for_startup?("removed.sqlite3")
    end
  end

  test "locked database detection skips prepare when the loaded recovery passphrase cannot unlock the database" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, true) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ encrypted_path.to_s ]) do
        SqlcipherDatabaseMigrator.stub(:encrypted_database_openable_with_current_key?, false) do
          assert_equal [ encrypted_path.to_s ], SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
        end
      end
    end
  end

  test "locked database detection allows prepare when the loaded recovery passphrase opens the database" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, true) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ encrypted_path.to_s ]) do
        SqlcipherDatabaseMigrator.stub(:encrypted_database_openable_with_current_key?, true) do
          assert_empty SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
        end
      end
    end
  end

  test "locked database detection uses the active record connection when the database is already open" do
    encrypted_path = @root.join("encrypted.sqlite3")
    File.binwrite(encrypted_path, "not a sqlite header")

    RecoverySecret.stub(:present?, true) do
      SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ encrypted_path.to_s ]) do
        SqlcipherDatabaseMigrator.stub(:accessible_via_active_record?, true) do
          SqlcipherDatabaseMigrator.stub(:encrypted_database_openable_with_current_key?, ->(*) { raise "should not open a second SQLCipher connection" }) do
            assert_empty SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: "production")
          end
        end
      end
    end
  end
end
