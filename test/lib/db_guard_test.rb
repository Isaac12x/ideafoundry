require "test_helper"
require "rake"

class DbGuardTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:dev_wipe_guard")
    @guard = Rake::Task["db:dev_wipe_guard"]
    @guard.reenable
  end

  test "aborts in development" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      error = assert_raises(SystemExit) { capture_io { @guard.invoke } }
      assert_equal 1, error.status
    end
  end

  test "allows development with the opt-in" do
    ENV["ALLOW_DEV_DB_WIPE"] = "1"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) { assert_nothing_raised { @guard.invoke } }
  ensure
    ENV.delete("ALLOW_DEV_DB_WIPE")
  end

  test "aborts in development with DATABASE_URL even with the opt-in" do
    ENV["ALLOW_DEV_DB_WIPE"] = "1"
    ENV["DATABASE_URL"] = "sqlite3:tmp/scratch.sqlite3"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      error = assert_raises(SystemExit) { capture_io { @guard.invoke } }
      assert_equal 1, error.status
    end
  ensure
    ENV.delete("ALLOW_DEV_DB_WIPE")
    ENV.delete("DATABASE_URL")
  end

  test "does nothing in test" do
    assert_nothing_raised { @guard.invoke }
  end

  test "wraps every destructive task but not db:test or db:prepare" do
    assert_includes Rake::Task["db:schema:load:queue"].prerequisites, "db:dev_wipe_guard"
    assert_includes Rake::Task["db:drop:_unsafe"].prerequisites, "db:dev_wipe_guard"
    assert_includes Rake::Task["db:fixtures:load"].prerequisites, "db:dev_wipe_guard"
    assert_not_includes Rake::Task["db:test:prepare"].prerequisites, "db:dev_wipe_guard"
    assert_not_includes Rake::Task["db:prepare"].prerequisites, "db:dev_wipe_guard"
  end
end
