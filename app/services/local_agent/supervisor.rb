module LocalAgent
  class Supervisor
    DEFAULT_RUNNER_PATH = Rails.root.join("..", "idea-app-agent", "bin", "idea-foundry-agent")

    def initialize(user:, run:)
      @user = user
      @run = run
    end

    def start(run_once: false)
      if Rails.env.test?
        mark_running_without_process(run_once: run_once)
        return run
      end

      unless File.executable?(runner_path)
        mark_failed!("Runner executable not found at #{runner_path}")
        return run
      end

      pid = Process.spawn(
        runner_environment(run_once: run_once),
        runner_path.to_s,
        *runner_arguments(run_once: run_once),
        chdir: Rails.root.to_s,
        out: Rails.root.join("log", "local_agent.log").to_s,
        err: [:child, :out]
      )
      Process.detach(pid)
      run.update!(pid: pid, status: :running, started_at: Time.current, last_heartbeat_at: Time.current)
      record_event!("started", "Started local agent runner", run_once: run_once, pid: pid)
      run
    rescue SystemCallError => e
      mark_failed!(e.message)
      run
    end

    private

    attr_reader :user, :run

    def runner_path
      Pathname.new(ENV.fetch("IDEA_FOUNDRY_AGENT_RUNNER_PATH", DEFAULT_RUNNER_PATH.to_s))
    end

    def runner_environment(run_once:)
      {
        "IDEA_FOUNDRY_AGENT_RUN_ID" => run.id.to_s,
        "IDEA_FOUNDRY_RAILS_URL" => ENV.fetch("IDEA_FOUNDRY_RAILS_URL", "http://127.0.0.1:3000"),
        "IDEA_FOUNDRY_AGENT_RUN_ONCE" => run_once ? "1" : "0"
      }
    end

    def runner_arguments(run_once:)
      args = ["--run-id", run.id.to_s]
      args << "--once" if run_once
      args
    end

    def mark_running_without_process(run_once:)
      run.update!(status: :running, started_at: Time.current, last_heartbeat_at: Time.current)
      record_event!("started", "Marked local agent run active in test", run_once: run_once)
    end

    def mark_failed!(message)
      run.update!(status: :failed, started_at: run.started_at || Time.current, stopped_at: Time.current)
      record_event!("error", message, runner_path: runner_path.to_s)
    end

    def record_event!(event_type, summary, payload = {})
      user.agent_events.create!(
        agent_run: run,
        event_type: event_type,
        summary: summary,
        payload: payload
      )
    end
  end
end
