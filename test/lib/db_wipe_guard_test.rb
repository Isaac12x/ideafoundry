require "test_helper"

class DbWipeGuardTest < ActiveSupport::TestCase
  self.use_transactional_tests = false # empty? opens a temporary pool on a tmpdir db
  Tasks = ActiveRecord::Tasks::DatabaseTasks

  def config(env, db = "storage/never_touched.sqlite3")
    ActiveRecord::DatabaseConfigurations::HashConfig.new(env, "primary", adapter: "sqlite3", database: db)
  end

  %w[development production].each do |env|
    test "#{env}: drop/purge/reconstruct/truncate refuse before touching anything" do
      c = config(env)
      assert_raises(DbWipeGuard::Refused) { Tasks.drop(c) }
      assert_raises(DbWipeGuard::Refused) { Tasks.purge(c) }
      assert_raises(DbWipeGuard::Refused) { Tasks.reconstruct_from_schema(c) }
      assert_raises(DbWipeGuard::Refused) { Tasks.truncate_all(env) }
    end
  end

  test "load_schema refuses a non-empty non-test db" do
    c = config("development")
    DbWipeGuard.stub(:empty?, false) do
      assert_raises(DbWipeGuard::Refused) { Tasks.load_schema(c) }
    end
  end

  test "empty? is true for a fresh dev db, false once it has tables (db:prepare vs wipe)" do
    Dir.mktmpdir do |dir|
      c = config("development", File.join(dir, "scratch.sqlite3"))
      assert DbWipeGuard.empty?(c, Tasks)
      SQLite3::Database.new(c.database).tap { |d| d.execute("create table t (id integer)") }.close
      assert_not DbWipeGuard.empty?(c, Tasks)
    end
  end

  test "spoofed test env is refused: test config pointing at a real file" do
    %w[storage/development.sqlite3 storage/production.sqlite3 storage/queue.sqlite3 storage/cache.sqlite3
       storage/development_test.sqlite3 storage/primary.sqlite3].each do |db|
      assert_raises(DbWipeGuard::Refused, db) { Tasks.drop(config("test", db)) }
    end
  end

  test "test-named files are exempt" do
    %w[storage/test.sqlite3 storage/test.sqlite3-3 storage/queue_test.sqlite3_2 storage/test_cache.sqlite3].each do |db|
      assert DbWipeGuard.test_db?(config("test", db)), db
    end
  end

  test "token match: latest.sqlite3 and contest.sqlite3 are not test files" do
    %w[storage/latest.sqlite3 storage/contest.sqlite3 storage/attest.sqlite3].each do |db|
      assert_not DbWipeGuard.test_db?(config("test", db)), db
    end
  end

  test "test file outside storage/tmp is refused" do
    assert_not DbWipeGuard.test_db?(config("test", "/var/data/test.sqlite3"))
    assert_not DbWipeGuard.test_db?(config("test", "../test.sqlite3"))
  end

  test "symlinked test file is refused" do
    link = Rails.root.join("tmp/guard_symlink_test.sqlite3").to_s
    File.symlink(Rails.root.join("storage").to_s, link)
    assert_not DbWipeGuard.test_db?(config("test", link))
    link2 = Rails.root.join("tmp/guard_link_test.sqlite3").to_s
    File.symlink("/etc/hosts", link2)
    assert_not DbWipeGuard.test_db?(config("test", link2))
  ensure
    [ link, link2 ].each { |l| File.unlink(l) if l && File.symlink?(l) }
  end

  test "SQLiteDatabaseTasks drop/purge refuse a non-test config before FileUtils.rm" do
    c = config("development", "tmp/never_touched_guard.sqlite3")
    t = ActiveRecord::Tasks::SQLiteDatabaseTasks.new(c, Rails.root)
    FileUtils.stub(:rm, ->(*) { flunk "rm called" }) do
      assert_raises(DbWipeGuard::Refused) { t.drop }
      assert_raises(DbWipeGuard::Refused) { t.purge }
    end
  end

  test "DATABASE_URL set refuses even a test config" do
    ENV["DATABASE_URL"] = "sqlite3:storage/development.sqlite3"
    assert_raises(DbWipeGuard::Refused) { Tasks.drop(config("test", "storage/test.sqlite3")) }
  ensure
    ENV.delete("DATABASE_URL")
  end

  test "test configs are exempt" do
    assert DbWipeGuard.deny!(:drop, config("test", "storage/test.sqlite3"))
    assert DbWipeGuard.deny!(:truncate_all, "test")
  end
end
