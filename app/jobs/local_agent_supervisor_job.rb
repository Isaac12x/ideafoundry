class LocalAgentSupervisorJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil, run_once: false)
    user = user_id.present? ? User.find(user_id) : User.first
    return unless user

    unless user.local_agent_enabled?
      stop_active_runs(user)
      return
    end

    mark_stale_runs(user)
    return if user.agent_runs.active.exists?

    run = user.agent_runs.create!(
      status: :starting,
      started_at: Time.current,
      metadata: { "run_once" => run_once }
    )
    LocalAgent::Supervisor.new(user: user, run: run).start(run_once: run_once)
  end

  private

  def stop_active_runs(user)
    user.agent_runs.where(status: [:starting, :running]).find_each do |run|
      run.stop!
      user.agent_events.create!(
        agent_run: run,
        event_type: "stopped",
        summary: "Stopped because local agent is disabled",
        payload: {}
      )
    end
  end

  def mark_stale_runs(user)
    user.agent_runs.where(status: [:starting, :running]).find_each do |run|
      next unless run.heartbeat_stale?

      run.update!(status: :stale, stopped_at: Time.current)
      user.agent_events.create!(
        agent_run: run,
        event_type: "stale",
        summary: "Marked stale after missed heartbeat",
        payload: { "last_heartbeat_at" => run.last_heartbeat_at }
      )
    end
  end
end
