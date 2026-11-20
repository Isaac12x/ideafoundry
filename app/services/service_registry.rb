require "net/http"
require "open3"
require "timeout"

# What the settings page can configure, plus per-service connection tests.
module ServiceRegistry
  # `fetch(env)` over unsaved form values, falling back to live settings.
  Overlay = Struct.new(:over) do
    def [](key) = over[key.to_s].presence || ServiceSettings.fetch(key)
    def fetch(key, default = nil) = self[key] || default
  end

  SERVICES = [
    { key: "voice_id", name: "Voice ID", kind: "http", probe: "/health",
      summary: "Local speech-to-text sidecar for voice capture.",
      fields: [ { env: "VOICE_ID_SERVICE_URL", label: "URL", default: LocalVoiceIdClient::DEFAULT_URL, hint: "Base URL of the voice-id service" } ],
      setup: [ "docker compose -f infra/docker-compose.yml up -d voice-id" ], docs: "infra/services/voice_id/README.md" },
    { key: "fluidvoice", name: "FluidVoice", kind: "http", probe: "/health",
      summary: "Optional dedicated /transcribe endpoint; blank uses the Voice ID URL.",
      fields: [ { env: "FLUIDVOICE_SERVICE_URL", label: "URL", default: nil, hint: "Blank = Voice ID service" } ],
      setup: [], docs: "infra/services/voice_id/README.md" },
    { key: "ocr", name: "OCR", kind: "http", probe: "/health",
      summary: "Surya OCR sidecar for attachments and KB files.",
      fields: [ { env: "OCR_SERVICE_URL", label: "URL", default: OcrClient::DEFAULT_URL, hint: "Extract endpoint (a trailing /extract is stripped for the health check)" },
                { env: "OCR_SERVICE_TIMEOUT", label: "Timeout (s)", default: "900", hint: "Read timeout for extraction" } ],
      setup: [ "docker compose -f infra/docker-compose.yml up -d ocr" ], docs: "infra/services/ocr/README.md" },
    { key: "long_ocr", name: "Long-document OCR", kind: "http", probe: "/models",
      summary: "Heavy Unlimited-OCR backend (vLLM, llama.cpp or a remote endpoint).",
      fields: [ { env: "OCR_LONG_BACKEND", label: "Backend", default: "auto", hint: "auto, vllm, llamacpp or remote" },
                { env: "OCR_LONG_SERVICE_URL", label: "Remote URL", default: nil, hint: "Already-running OpenAI-compatible /v1 endpoint; forces remote in auto mode" },
                { env: "OCR_LONG_VLLM_URL", label: "vLLM URL", default: LongOcr::Backend::DEFAULTS[:vllm][:url], hint: "" },
                { env: "OCR_LONG_LLAMACPP_URL", label: "llama.cpp URL", default: LongOcr::Backend::DEFAULTS[:llamacpp][:url], hint: "" } ],
      setup: [ "docker compose -f infra/docker-compose.yml --profile gpu up -d unlimited-ocr-llama" ], docs: "infra/services/long_ocr/README.md" },
    { key: "semantic", name: "Semantic search", kind: "http", probe: "/health",
      summary: "Embedding + vector sidecar for palette Similar. Off while the URL is blank.",
      fields: [ { env: "SEMANTIC_SERVICE_URL", label: "URL", default: nil, hint: "e.g. http://localhost:8004" } ],
      setup: [ "docker compose -f infra/docker-compose.yml up -d semantic" ], docs: "infra/services/semantic/README.md" },
    { key: "whisper", name: "Whisper", kind: "bin", probe: [ "--help" ],
      summary: "Local whisper CLI for KB audio/video transcripts.",
      fields: [ { env: "WHISPER_BIN", label: "Binary", default: "whisper", hint: "Path or name on PATH" },
                { env: "WHISPER_MODEL", label: "Model", default: "base", hint: "Downloaded on first use" } ],
      setup: [ "pipx install openai-whisper" ], docs: "docs/guide/services.md" },
    { key: "ebook_convert", name: "Calibre ebook-convert", kind: "bin", probe: [ "--version" ],
      summary: "Converts non-EPUB ebooks for the KB viewer.",
      fields: [ { env: "EBOOK_CONVERT_BIN", label: "Binary", default: "ebook-convert", hint: "Path or name on PATH" } ],
      setup: [ "brew install --cask calibre" ], docs: "docs/guide/services.md" },
    { key: "ddjvu", name: "DjVuLibre ddjvu", kind: "bin", probe: [ "--help" ],
      summary: "Converts .djvu to PDF for the KB viewer.",
      fields: [ { env: "DDJVU_BIN", label: "Binary", default: "ddjvu", hint: "Path or name on PATH" } ],
      setup: [ "brew install djvulibre" ], docs: "docs/guide/services.md" }
  ].freeze

  module_function

  def env_keys = SERVICES.flat_map { |s| s[:fields].map { |f| f[:env] } }

  def find(key) = SERVICES.find { |s| s[:key] == key.to_s }

  def view_model
    overrides = ServiceSetting.where(key: env_keys).pluck(:key, :value).to_h
    SERVICES.map do |s|
      s.merge(fields: s[:fields].map do |f|
        f.merge(value: ServiceSettings.fetch(f[:env], f[:default]), override: overrides[f[:env]].presence,
                source: ServiceSettings.source(f[:env]).then { |src| src == "unset" && f[:default] ? "default" : src })
      end)
    end
  end

  # -> { ok:, status: "ok"|"error"|"off", detail:, ms: }; overrides = unsaved form values { ENV_KEY => v }
  def test(key, overrides = {})
    service = find(key) or return result(false, "error", "Unknown service", 0)
    env = Overlay.new(overrides.to_h.stringify_keys.slice(*service[:fields].map { |f| f[:env] }))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, detail = service[:kind] == "bin" ? probe_bin(service, env) : probe_http(service, env)
    result(status == "ok", status, detail, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
  rescue StandardError => e
    result(false, "error", "#{e.class}: #{e.message}", 0)
  end

  def result(ok, status, detail, ms) = { ok: ok, status: status, detail: detail, ms: ms }

  def probe_http(service, env)
    url = http_base(service, env)
    return [ "off", "No URL set" ] if url.blank?

    uri = URI.parse(url)
    return [ "error", "only http(s) URLs" ] unless uri.is_a?(URI::HTTP) && uri.host

    uri.path = "#{uri.path.chomp('/')}#{service[:probe]}"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 2) { |http| http.get(uri.request_uri) }
    res.is_a?(Net::HTTPSuccess) ? [ "ok", "#{uri} -> HTTP #{res.code}" ] : [ "error", "#{uri} -> HTTP #{res.code}" ]
  rescue URI::InvalidURIError
    [ "error", "only http(s) URLs" ]
  rescue SystemCallError, SocketError, Timeout::Error, IOError => e
    [ "error", "#{e.class.name.demodulize}: #{e.message}" ]
  end

  # Health lives at the service root, so drop an endpoint suffix (/extract, /v1). Long OCR is probed at its /v1 base.
  def http_base(service, env)
    field = ->(i) { service[:fields][i] }
    case service[:key]
    when "long_ocr" then LongOcr::Backend.new(env: env).base_url
    when "fluidvoice" then env[field.(0)[:env]]
    else env.fetch(field.(0)[:env], field.(0)[:default]).to_s.sub(%r{/(extract|v1)/?\z}, "").chomp("/")
    end
  end

  def probe_bin(service, env)
    f = service[:fields].first
    configured = env.fetch(f[:env], f[:default])
    path = (configured if File.file?(configured) && File.executable?(configured)) || Kb::LocalTool.path(File.basename(configured))
    return [ "error", "#{configured} not found" ] unless path

    Open3.popen2e(path, *service[:probe]) do |stdin, out, wait|
      stdin.close
      unless wait.join(5)
        Process.kill("KILL", wait.pid) rescue nil # don't leave a hung tool running
        return [ "error", "#{path} timed out after 5s" ]
      end
      [ "ok", "#{path}: #{out.read.lines.map(&:strip).find(&:present?) || 'ran'}" ]
    end
  end
end
