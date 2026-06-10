require "test_helper"

class LocalAgentSupervisorJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @user.update!(settings: {})
  end

  test "does not create a duplicate run when an active heartbeat exists" do
    @user.update_local_agent_settings("enabled" => "1")
    run = @user.agent_runs.create!(
      status: :running,
      pid: 12345,
      started_at: 1.minute.ago,
      last_heartbeat_at: Time.current
    )

    assert_no_difference "AgentRun.count" do
      LocalAgentSupervisorJob.perform_now(@user.id)
    end

    assert_equal run, @user.agent_runs.active.first
  end

  test "marks active runs stopped when local agent is disabled" do
    @user.update_local_agent_settings("enabled" => "0")
    run = @user.agent_runs.create!(
      status: :running,
      pid: 12345,
      started_at: 1.minute.ago,
      last_heartbeat_at: Time.current
    )

    LocalAgentSupervisorJob.perform_now(@user.id)

    assert run.reload.stopped?
    assert_not_nil run.stopped_at
  end
end
