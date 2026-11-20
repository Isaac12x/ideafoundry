require "test_helper"

class ApplicationJobRecoveryTest < ActiveJob::TestCase
  class ProbeJob < ApplicationJob
    def perform = nil
  end

  test "job drops connections when another process changed the recovery generation" do
    path = Rails.root.join("tmp/recovery_generation_job_test_#{SecureRandom.hex(4)}")
    RecoverySecret.stub(:generation_path, path) do
      RecoverySecret.bump_generation!
      refute RecoverySecret.reset_connections_if_changed!

      File.write(path, "bumped-by-web-worker")
      disconnected = []
      pools = ActiveRecord::Base.connection_handler.connection_pool_list
      pools.each { |pool| pool.define_singleton_method(:disconnect) { |*| disconnected << self } }

      ProbeJob.perform_now

      assert_equal pools.size, disconnected.size
      refute RecoverySecret.reset_connections_if_changed!, "reported once"
    end
  ensure
    FileUtils.rm_f(path)
  end
end
