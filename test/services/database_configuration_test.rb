require "test_helper"

class DatabaseConfigurationTest < ActiveSupport::TestCase
  test "development and production queue databases do not share a file" do
    configurations = ActiveRecord::Base.configurations
    development_queue = configurations.configs_for(env_name: "development", name: "queue").database
    production_queue = configurations.configs_for(env_name: "production", name: "queue").database

    refute_equal production_queue, development_queue
  end

  test "development and production cache databases do not share a file" do
    configurations = ActiveRecord::Base.configurations
    development_cache = configurations.configs_for(env_name: "development", name: "cache").database
    production_cache = configurations.configs_for(env_name: "production", name: "cache").database

    refute_equal production_cache, development_cache
  end

  # A `busy_timeout` pragma replaces the busy handler Rails installs from
  # `timeout` with SQLite's own, which sleeps holding the GVL. One blocked
  # writer then freezes every thread in the process -- including the one holding
  # the write lock -- and Solid Queue's pollers die with "database is locked".
  test "every database waits for locks with the GVL-releasing busy handler" do
    ActiveRecord::Base.configurations.configs_for(include_hidden: true).each do |config|
      label = "#{config.env_name}/#{config.name}"
      pragmas = (config.configuration_hash[:pragmas] || {}).stringify_keys

      assert_nil pragmas["busy_timeout"], "#{label} sets the GVL-holding busy_timeout pragma"
      assert_kind_of Integer, config.configuration_hash[:timeout], "#{label} has no lock timeout"
    end
  end

  test "connected databases have no SQLite-level busy timeout installed" do
    [ [ ActiveRecord::Base, "primary" ], [ SolidQueue::Job, "queue" ] ].each do |klass, label|
      klass.with_connection do |connection|
        assert_equal 0, connection.raw_connection.get_first_value("PRAGMA busy_timeout"),
          "#{label} waits for locks inside SQLite instead of in Ruby"
      end
    end
  end
end
