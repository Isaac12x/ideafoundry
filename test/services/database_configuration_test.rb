require "test_helper"

class DatabaseConfigurationTest < ActiveSupport::TestCase
  test "development and production queue databases do not share a file" do
    configurations = ActiveRecord::Base.configurations
    development_queue = configurations.configs_for(env_name: "development", name: "queue").database
    production_queue = configurations.configs_for(env_name: "production", name: "queue").database

    refute_equal production_queue, development_queue
  end
end
