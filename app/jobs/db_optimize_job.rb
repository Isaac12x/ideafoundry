# Keeps SQLite's query planner statistics fresh (ANALYZE) and trims what changed (PRAGMA optimize).
class DbOptimizeJob < ApplicationJob
  queue_as :default

  def perform
    [ ApplicationRecord ].each do |klass|
      klass.connection.execute("PRAGMA optimize")
    end
    ActiveRecord::Base.connection.execute("ANALYZE") # full stats once a day is cheap on a single-user DB
  end
end
