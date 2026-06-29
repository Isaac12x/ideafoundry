require "open3"

module LongOcr
  # Brings the heavy OCR backend up on demand and tears it down when idle.
  #
  # For vllm/llamacpp this drives `docker compose` (start/stop a sidecar that is
  # kept out of the default compose graph). For a remote backend it only checks
  # reachability. Requires docker CLI access on whatever host runs the worker;
  # when that is unavailable the job surfaces a clear error rather than hanging.
  class ServiceSupervisor
    class Error < StandardError; end

    # Serialize compose up/down so concurrent jobs share one running instance.
    @mutex = Mutex.new
    class << self
      attr_reader :mutex
    end

    def initialize(backend: Backend.current, client: nil, logger: Rails.logger)
      @backend = backend
      @client = client || Client.new(backend: backend)
      @logger = logger
    end

    # Ensure the backend is reachable, starting the container if needed.
    def ensure_up!
      return wait_ready!(reason: "remote backend unreachable") unless @backend.manages_lifecycle?
      return true if @client.ready?

      self.class.mutex.synchronize do
        return true if @client.ready?

        @logger&.info("[long_ocr] starting backend #{@backend} (#{@backend.compose_service})")
        run_compose!("--profile", @backend.compose_profile, "up", "-d", @backend.compose_service)
        wait_ready!(reason: "backend #{@backend} did not become ready")
      end
    end

    # Stop the container if it is managed and currently idle.
    def stop!
      return unless @backend.manages_lifecycle?

      @logger&.info("[long_ocr] stopping backend #{@backend} (#{@backend.compose_service})")
      run_compose!("stop", @backend.compose_service)
    end

    def ready?
      @client.ready?
    end

    private

    def wait_ready!(reason:)
      deadline = Time.current + startup_timeout
      until @client.ready?
        raise Error, reason if Time.current > deadline

        sleep poll_interval
      end
      true
    end

    def run_compose!(*args)
      cmd = compose_base + args
      stdout, stderr, status = Open3.capture3(*cmd, chdir: Rails.root.to_s)
      return stdout if status.success?

      raise Error, "compose failed (#{cmd.join(' ')}): #{stderr.presence || stdout}"
    end

    def compose_base
      ENV.fetch("OCR_LONG_COMPOSE_CMD", "docker compose").split + ["-f", compose_file]
    end

    def compose_file
      ENV.fetch("OCR_LONG_COMPOSE_FILE", Rails.root.join("docker-compose.yml").to_s)
    end

    def startup_timeout
      ENV.fetch("OCR_LONG_STARTUP_TIMEOUT", "900").to_i
    end

    def poll_interval
      ENV.fetch("OCR_LONG_POLL_INTERVAL", "3").to_i
    end
  end
end
