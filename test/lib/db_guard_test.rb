require "test_helper"
require "rake"

class DbGuardTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:wipe_guard")
    @guard = Rake::Task["db:wipe_guard"]
    @guard.reenable
  end

  teardown do
    ENV.delete("DISABLE_DATABASE_ENVIRONMENT_CHECK")
    ENV.delete("DATABASE_URL")
  end

  %w[development production].each do |env|
    test "aborts in #{env} with no opt-in" do
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(env)) do
        assert_equal 1, assert_raises(SystemExit) { capture_io { @guard.invoke } }.status
      end
    end

    test "aborts in #{env} even with DISABLE_DATABASE_ENVIRONMENT_CHECK" do
      ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "1"
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(env)) do
        assert_raises(SystemExit) { capture_io { @guard.invoke } }
      end
    end
  end

  test "aborts in development with DATABASE_URL" do
    ENV["DATABASE_URL"] = "sqlite3:tmp/scratch.sqlite3"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      assert_raises(SystemExit) { capture_io { @guard.invoke } }
    end
  end

  test "aborts in test env when DATABASE_URL is set" do
    ENV["DATABASE_URL"] = "sqlite3:storage/development.sqlite3"
    assert_raises(SystemExit) { capture_io { @guard.invoke } }
  end

  test "aborts when a test-env config points at a non-test file" do
    cfg = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", adapter: "sqlite3", database: "storage/development.sqlite3")
    ActiveRecord::Base.configurations.stub(:configs_for, [ cfg ]) do
      assert_raises(SystemExit) { capture_io { @guard.invoke } }
    end
  end

  test "does nothing in test" do
    assert_nothing_raised { @guard.invoke }
  end

  test "wraps every destructive task first, not forward/test tasks" do
    %w[db:schema:load db:schema:load:queue db:reset db:reset:all db:drop db:drop:_unsafe db:drop:all db:purge db:purge:all
       db:setup db:setup:queue db:truncate_all db:seed:replant db:migrate:reset db:migrate:redo db:migrate:down
       db:rollback db:rollback:primary db:fixtures:load].each do |name|
      assert_equal "db:wipe_guard", Rake::Task[name].prerequisites.first, name
    end
    %w[db:test:prepare db:prepare db:migrate:up db:create db:seed].each do |name|
      assert_not_includes Rake::Task[name].prerequisites, "db:wipe_guard", name
    end
  end

  test "VERSION = current-1 aborts outside test (stubbed, no migration)" do
    ENV["VERSION"] = "41"
    ctx = Struct.new(:current_version).new(42)
    pool = Struct.new(:migration_context).new(ctx)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      ActiveRecord::Base.stub(:connection_pool, pool) do
        Rake::Task["db:migrate_down_guard"].reenable
        assert_raises(SystemExit) { capture_io { Rake::Task["db:migrate_down_guard"].invoke } }
      end
    end
  ensure
    ENV.delete("VERSION")
  end

  test "db:migrate with VERSION below current aborts outside test" do
    ENV["VERSION"] = "0"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      Rake::Task["db:migrate_down_guard"].reenable
      assert_raises(SystemExit) { capture_io { Rake::Task["db:migrate_down_guard"].invoke } }
    end
  ensure
    ENV.delete("VERSION")
  end
end
