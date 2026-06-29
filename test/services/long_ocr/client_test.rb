require "test_helper"

class LongOcrClientTest < ActiveSupport::TestCase
  def vllm_client
    LongOcr::Client.new(backend: LongOcr::Backend.new(env: { "OCR_LONG_BACKEND" => "vllm" }))
  end

  test "prompt is the exact recipe string for a single image" do
    assert_equal "<image>document parsing.", vllm_client.send(:prompt_for, 1)
  end

  test "prompt prepends one <image> token per page for multi-image" do
    assert_equal "<image><image><image>document parsing.", vllm_client.send(:prompt_for, 3)
  end

  test "payload carries all images and recipe xargs for vllm" do
    payload = vllm_client.send(:payload, %w[a b])
    content = payload.dig(:messages, 0, :content)

    assert_equal 2, content.count { |part| part[:type] == "image_url" }
    assert_equal 0.0, payload[:temperature]
    assert_equal false, payload[:skip_special_tokens]
    assert_equal 35, payload.dig(:vllm_xargs, :ngram_size)
    assert_equal 1024, payload.dig(:vllm_xargs, :window_size)
  end

  test "non-vllm backend omits vllm-only xargs" do
    client = LongOcr::Client.new(backend: LongOcr::Backend.new(env: { "OCR_LONG_BACKEND" => "llamacpp" }))
    payload = client.send(:payload, %w[a])

    assert_nil payload[:skip_special_tokens]
    assert_nil payload[:vllm_xargs]
  end
end
