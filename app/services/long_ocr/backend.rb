module LongOcr
  # Resolves which heavy Unlimited-OCR backend to use and exposes the connection
  # details every other LongOcr class needs. Three backends, all speaking an
  # OpenAI-compatible /v1 chat API:
  #
  #   vllm     - local NVIDIA box, recipe image vllm/vllm-openai:unlimited-ocr
  #   llamacpp - Apple Silicon / CPU port via llama-server + GGUF (Metal)
  #   remote   - an already-running endpoint addressed by OCR_LONG_SERVICE_URL
  #
  # Selection (OCR_LONG_BACKEND): auto|vllm|llamacpp|remote. In auto mode a
  # configured OCR_LONG_SERVICE_URL forces remote, otherwise an NVIDIA GPU
  # selects vllm and everything else falls back to the llama.cpp port.
  class Backend
    DEFAULTS = {
      vllm: {
        url: "http://127.0.0.1:8002/v1",
        model: "baidu/Unlimited-OCR",
        service: "unlimited-ocr",
        profile: "gpu"
      },
      llamacpp: {
        url: "http://127.0.0.1:8003/v1",
        model: "unlimited-ocr",
        service: "unlimited-ocr-llama",
        profile: "gpu"
      }
    }.freeze

    attr_reader :name, :base_url, :model

    def self.current
      new
    end

    def initialize(env: ENV)
      @env = env
      @name = resolve_name
      config = DEFAULTS[@name] || {}
      @base_url = (remote_url.presence if @name == :remote) || @env.fetch("OCR_LONG_#{@name.to_s.upcase}_URL", config[:url])
      @base_url = @base_url.chomp("/")
      @model = @env.fetch("OCR_LONG_MODEL", config[:model] || "unlimited-ocr")
      @config = config
    end

    def remote?
      name == :remote
    end

    def vllm?
      name == :vllm
    end

    # Only vllm/llamacpp are container-managed on demand; a remote endpoint is
    # assumed to be provisioned/autoscaled externally.
    def manages_lifecycle?
      !remote?
    end

    def compose_service
      @config[:service]
    end

    def compose_profile
      @env.fetch("OCR_LONG_COMPOSE_PROFILE", @config[:profile] || "gpu")
    end

    def window_size
      @env.fetch("OCR_LONG_WINDOW_SIZE", "1024").to_i
    end

    def ngram_size
      @env.fetch("OCR_LONG_NGRAM_SIZE", "35").to_i
    end

    def max_tokens
      @env.fetch("OCR_LONG_MAX_TOKENS", "8192").to_i
    end

    def to_s
      name.to_s
    end

    private

    def remote_url
      @env["OCR_LONG_SERVICE_URL"]
    end

    def resolve_name
      explicit = @env.fetch("OCR_LONG_BACKEND", "auto").to_s.downcase
      return explicit.to_sym if %w[vllm llamacpp remote].include?(explicit)

      return :remote if remote_url.present?
      return :vllm if nvidia_gpu?

      :llamacpp
    end

    def nvidia_gpu?
      return true if @env["OCR_LONG_FORCE_NVIDIA"] == "1"
      return false if @env["OCR_LONG_FORCE_NVIDIA"] == "0"

      File.exist?("/proc/driver/nvidia/version") ||
        File.exist?("/dev/nvidia0") ||
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "nvidia-smi")) }
    end
  end
end
