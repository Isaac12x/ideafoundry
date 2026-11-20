ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "active_support/testing/event_reporter_assertions"
require "minitest/mock"

module ActiveSupport
  class TestCase
    include ActiveSupport::Testing::EventReporterAssertions

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # tmp/recovery_generation is a cross-process signal; a sibling worker bumping it makes this one drop its
    # test-transaction connection mid-test (state vanishes). Give each worker its own file.
    parallelize_setup do |worker|
      path = Rails.root.join("tmp", "recovery_generation_test_#{worker}")
      RecoverySecret.define_singleton_method(:generation_path) { path }
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # The recovery probe memo (ApplicationController) must not leak a "nothing locked" result between tests.
    setup { ApplicationController.recovery_probe_memo = nil }

    # Add more helper methods to be used by all tests here...
  end
end
