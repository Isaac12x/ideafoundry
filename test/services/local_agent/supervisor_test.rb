require "test_helper"

class LocalAgent::SupervisorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @run = @user.agent_runs.create!(status: :starting)
    @supervisor = LocalAgent::Supervisor.new(user: @user, run: @run)
  end

  test "default runner is the embedded executable" do
    runner_path = Rails.root.join("agent_runtime", "bin", "idea-foundry-agent")

    assert_equal runner_path, @supervisor.send(:runner_path)
    assert File.executable?(runner_path)
  end

  test "runner receives the run id in both argv and environment" do
    assert_equal [ "--run-id", @run.id.to_s ], @supervisor.send(:runner_arguments, run_once: false)
    assert_equal [ "--run-id", @run.id.to_s, "--once" ], @supervisor.send(:runner_arguments, run_once: true)

    environment = @supervisor.send(:runner_environment, run_once: true)
    assert_equal @run.id.to_s, environment.fetch("IDEA_FOUNDRY_AGENT_RUN_ID")
    assert_equal "1", environment.fetch("IDEA_FOUNDRY_AGENT_RUN_ONCE")
  end
end
