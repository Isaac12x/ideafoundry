require "net/http"
require "json"
require "base64"

module LongOcr
  # Thin OpenAI-compatible chat client for the heavy OCR backend. One page (PNG
  # bytes) per call; returns cleaned markdown. Works against vLLM, llama-server,
  # or a remote endpoint identically — only the vLLM-specific logits-processor
  # xargs are added when the selected backend is vllm.
  class Client
    class Error < StandardError; end

    # Recipe literal suffix; one "<image>" token is prepended per image so the
    # text matches the recipe exactly for single-image and generalizes to the
    # multi-image (base mode) path used for whole-document requests.
    PROMPT_SUFFIX = "document parsing.".freeze

    def initialize(backend: Backend.current, timeout: ENV.fetch("OCR_LONG_TIMEOUT", "1800").to_i)
      @backend = backend
      @timeout = timeout
    end

    # GET /v1/models — used by the supervisor to detect readiness.
    def ready?
      uri = URI("#{@backend.base_url}/models")
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 5) do |http|
        http.request(Net::HTTP::Get.new(uri)).is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end

    # OCR a single page image, returning cleaned markdown.
    def ocr_page(png_bytes)
      ocr_pages([png_bytes])
    end

    # OCR one or more page images in a single request. With >=2 images the
    # server auto-falls back to non-crop (base) mode; window_size=1024 (set per
    # the recipe via the backend) matches that multi-page path.
    def ocr_pages(images)
      images = Array(images)
      raise Error, "ocr_pages requires at least one image" if images.empty?

      body = JSON.dump(payload(images))
      uri = URI("#{@backend.base_url}/chat/completions")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: @timeout, open_timeout: 10) do |http|
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Long-OCR backend (#{@backend}) returned #{response.code}: #{response.body.to_s.truncate(200)}"
      end

      content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
      Grounding.to_markdown(content)
    rescue JSON::ParserError => e
      raise Error, "Long-OCR backend returned invalid JSON: #{e.message}"
    end

    private

    def payload(images)
      content = [{ type: "text", text: prompt_for(images.length) }]
      images.each do |png_bytes|
        data_url = "data:image/png;base64,#{Base64.strict_encode64(png_bytes)}"
        content << { type: "image_url", image_url: { url: data_url } }
      end

      base = {
        model: @backend.model,
        messages: [{ role: "user", content: content }],
        max_tokens: @backend.max_tokens,
        temperature: 0.0
      }
      base.merge(extra_body)
    end

    # One "<image>" placeholder per image, then the recipe suffix. n=1 yields
    # the exact recipe string "<image>document parsing.".
    def prompt_for(count)
      ("<image>" * count) + PROMPT_SUFFIX
    end

    # vLLM needs the special-token + n-gram window flags from the recipe; other
    # backends ignore unknown fields, so we only send them for vllm.
    def extra_body
      return {} unless @backend.vllm?

      {
        skip_special_tokens: false,
        vllm_xargs: { ngram_size: @backend.ngram_size, window_size: @backend.window_size }
      }
    end
  end
end
