require "test_helper"

class DbOptimizeJobTest < ActiveJob::TestCase
  test "runs ANALYZE and PRAGMA optimize without error" do
    assert_nothing_raised { DbOptimizeJob.perform_now }
  end
end
