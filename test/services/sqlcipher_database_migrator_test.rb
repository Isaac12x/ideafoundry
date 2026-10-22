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
    SqlcipherDatabaseMigrator.release_retained_locks!
    FileUtils.rm_rf(@root) if @root&.exist?
  end

  def key_hex = RecoverySecret.sqlcipher_key_hex
  def new_key_hex = "ab" * 32

  # A second process that keeps the database open until it is killed.
  def with_other_process_holding(path)
    reader, writer = IO.pipe
    pid = Process.spawn(RbConfig.ruby, "-e", "f = File.open(ARGV[0]); puts :ready; $stdout.flush; sleep", path.to_s, out: writer)
    writer.close
    reader.gets
    yield
  ensure
    Process.kill("TERM", pid) if pid
    Process.wait(pid) if pid
    reader&.close
  end

  def migrator = SqlcipherDatabaseMigrator.new(key_hex: RecoverySecret.sqlcipher_key_hex, timestamp: "20260518123045")
  def files_under_root = Dir.glob(@root.join("**/*").to_s, File::FNM_DOTMATCH).select { |f| File.file?(f) }.map { |f| File.basename(f) }.sort

  def second_plaintext_database
    path = @root.join("queue.sqlite3")
    db = SQLite3::Database.new(path.to_s)
    db.execute("CREATE TABLE jobs (id integer primary key)")
    db.close
    path
  end

  def opens_with?(path, key)
    db = SQLite3::Database.new(path.to_s)
    db.execute(%(PRAGMA key = "x'#{key}'"))
    db.get_first_value("SELECT count(*) FROM sqlite_master")
    true
  rescue SQLite3::Exception
    false
  ensure
    db&.close
  end

  test "a partial migration (one database encrypted, one still plaintext) is detected per database and converges" do
    other = second_plaintext_database
    migrator.migrate!(@database_path) # the first database was converted before the run died
    SqlcipherDatabaseMigrator.release_retained_locks!
    converted = File.binread(@database_path)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @database_path.to_s, other.to_s ]) do
      statuses = migrator.configured_statuses(env: "production").map(&:status)
      assert_equal [ :encrypted, :plaintext ], statuses

      results = migrator.migrate_configured!(env: "production")
      assert_equal [ :already_encrypted, :encrypted ], results.map(&:status)
    end

    assert_equal converted, File.binread(@database_path), "the converted database is not rewritten"
    assert opens_with?(other, key_hex)
  end

  test "migrate_configured! is all or nothing: one blocked database leaves every database untouched" do
    other = second_plaintext_database
    File.write(@root.join(".queue.sqlite3.20260518123045.sqlcipher"), "stale")
    before = File.binread(@database_path)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @database_path.to_s, other.to_s ]) do
      assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.migrate_configured!(env: "production") }
    end

    assert_equal before, File.binread(@database_path)
    assert_equal "SQLite format 3\0", File.binread(other, 16)
  end

  test "rekey_configured! is all or nothing: a database that opens with neither key blocks every rekey" do
    other = second_plaintext_database
    migrator.migrate!(@database_path)
    SqlcipherDatabaseMigrator.new(key_hex: "cd" * 32).migrate!(other) # unknown key
    SqlcipherDatabaseMigrator.release_retained_locks!
    before = File.binread(@database_path)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @database_path.to_s, other.to_s ]) do
      assert_raises(SqlcipherDatabaseMigrator::Error) do
        SqlcipherDatabaseMigrator.rekey_configured!(env: "production", old_key_hex: key_hex, new_key_hex: new_key_hex)
      end
    end

    assert_equal before, File.binread(@database_path)
    assert opens_with?(@database_path, key_hex)
  end

  test "rekey converges after a partial run: already converted databases are skipped" do
    other = second_plaintext_database
    migrator.migrate!(@database_path)
    migrator.migrate!(other)
    SqlcipherDatabaseMigrator.release_retained_locks!
    migrator.rekey!(@database_path, new_key_hex: new_key_hex) # simulate a run that died after the first database
    SqlcipherDatabaseMigrator.release_retained_locks!
    converted = File.binread(@database_path)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @database_path.to_s, other.to_s ]) do
      SqlcipherDatabaseMigrator.rekey_configured!(env: "production", old_key_hex: key_hex, new_key_hex: new_key_hex)
    end

    assert_equal converted, File.binread(@database_path), "an already converted database is not rewritten"
    assert opens_with?(@database_path, new_key_hex)
    assert opens_with?(other, new_key_hex)
    assert_not opens_with?(other, key_hex)
  end

  test "ensure_no_other_openers! runs again after the lock and before the rename" do
    calls = []
    SqlcipherDatabaseMigrator.stub(:ensure_no_other_openers!, ->(*) { calls << :check }) do
      migrator.migrate!(@database_path)
    end

    assert_equal 3, calls.size, "once up front, once under the lock, once right before the rename"
  end

  test "the old sidecars are removed only after a successful rename" do
    FileUtils.touch("#{@database_path}-wal")
    FileUtils.touch("#{@database_path}-shm")
    File.stub(:rename, ->(*) { raise Errno::EACCES }) do
      assert_raises(Errno::EACCES) { migrator.migrate!(@database_path) }
    end
    assert File.exist?("#{@database_path}-shm"), "sidecars stay when the rename fails"

    migrator.migrate!(@database_path)
    assert_not File.exist?("#{@database_path}-shm"), "stale sidecars are removed after the rename"
    assert opens_with?(@database_path, key_hex)
  end

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

  test "a row that only lives in the WAL survives" do
    wal_path = @root.join("wal.sqlite3")
    other = SQLite3::Database.new(wal_path.to_s)
    other.execute("PRAGMA journal_mode = wal")
    other.execute("PRAGMA wal_autocheckpoint = 0")
    other.execute("CREATE TABLE ideas (id integer primary key, title text)")
    other.execute("INSERT INTO ideas (title) VALUES ('only in the wal')")
    assert File.size?("#{wal_path}-wal"), "row must still be in the WAL"

    migrator.migrate!(wal_path)

    db = SQLite3::Database.new(wal_path.to_s)
    db.execute(%(PRAGMA key = "x'#{key_hex}'"))
    assert_equal [ [ "only in the wal" ] ], db.execute("SELECT title FROM ideas")
  ensure
    other&.close
    db&.close
  end

  test "no other connection can write between export and rename, nor after the rename through a stale handle" do
    other = SQLite3::Database.new(@database_path.to_s)
    other.busy_timeout = 0
    blocked = nil
    m = migrator
    real = m.method(:verify_encrypted_database!)
    m.stub(:verify_encrypted_database!, lambda { |*args|
      # the temp copy is verified inside the lock window; the first call (is it plaintext?) happens before it
      if args.first.to_s.end_with?(".sqlcipher")
        blocked = assert_raises(SQLite3::BusyException) { other.execute("INSERT INTO ideas (title) VALUES ('sneaky')") }
      end
      real.call(*args)
    }) do
      m.migrate!(@database_path)
    end

    assert blocked, "a writer must be refused while the export is being verified"
    assert_raises(SQLite3::BusyException) { other.execute("INSERT INTO ideas (title) VALUES ('stale handle')") }

    db = SQLite3::Database.new(@database_path.to_s)
    db.execute(%(PRAGMA key = "x'#{key_hex}'"))
    assert_equal [ [ "Encrypted from app" ] ], db.execute("SELECT title FROM ideas")
  ensure
    other&.close
    db&.close
  end

  test "refuses, touching nothing, while another process has the database open" do
    before = File.binread(@database_path)

    with_other_process_holding(@database_path) do
      error = assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.migrate!(@database_path) }
      assert_match(/in use by process/, error.message)
    end

    assert_equal before, File.binread(@database_path)
    assert_equal [ "production.sqlite3" ], files_under_root
  end

  test "refuses to run when lsof is unavailable" do
    Open3.stub(:capture3, ->(*) { raise Errno::ENOENT }) do
      assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.migrate!(@database_path) }
    end
    assert_equal [ "production.sqlite3" ], files_under_root
  end

  test "a stale temporary file is never overwritten or removed" do
    stale = @root.join(".production.sqlite3.20260518123045.sqlcipher")
    File.write(stale, "stale")

    assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.migrate!(@database_path) }

    assert_equal "stale", File.read(stale)
    assert_equal "SQLite format 3\0", File.binread(@database_path, 16)
  end

  test "refuses to replace the database when per-table row counts differ" do
    copy = @root.join("copy.sqlite3")
    db = SQLite3::Database.new(copy.to_s)
    db.execute(%(PRAGMA key = "x'#{key_hex}'"))
    db.execute("CREATE TABLE ideas (id integer primary key, title text)")
    source = SQLite3::Database.new(@database_path.to_s)

    assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.send(:verify_same_row_counts!, source, copy, key_hex) }
  ensure
    db&.close
    source&.close
  end

  test "rekey! re-encrypts through the same safe path" do
    migrator.migrate!(@database_path)
    SqlcipherDatabaseMigrator.release_retained_locks!

    migrator.rekey!(@database_path, new_key_hex: new_key_hex)

    assert_equal [ "production.sqlite3" ], files_under_root
    db = SQLite3::Database.new(@database_path.to_s)
    db.execute(%(PRAGMA key = "x'#{new_key_hex}'"))
    assert_equal [ [ "Encrypted from app" ] ], db.execute("SELECT title FROM ideas")
    db.close
    old = SQLite3::Database.new(@database_path.to_s)
    old.execute(%(PRAGMA key = "x'#{key_hex}'"))
    assert_raises(SQLite3::NotADatabaseException) { old.execute("SELECT count(*) FROM sqlite_master") }
  ensure
    db&.close
    old&.close
  end

  test "rekey! refuses while another process has the database open" do
    migrator.migrate!(@database_path)
    SqlcipherDatabaseMigrator.release_retained_locks!
    before = File.binread(@database_path)

    with_other_process_holding(@database_path) do
      assert_raises(SqlcipherDatabaseMigrator::Error) { migrator.rekey!(@database_path, new_key_hex: new_key_hex) }
    end

    assert_equal before, File.binread(@database_path)
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
