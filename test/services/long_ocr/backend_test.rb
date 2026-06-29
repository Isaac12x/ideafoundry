require "test_helper"

class LongOcrBackendTest < ActiveSupport::TestCase
  test "configured service URL selects the remote backend with no lifecycle" do
    backend = LongOcr::Backend.new(env: { "OCR_LONG_SERVICE_URL" => "http://gpu-host:9000/v1" })

    assert backend.remote?
    assert_equal :remote, backend.name
    assert_equal "http://gpu-host:9000/v1", backend.base_url
    assert_not backend.manages_lifecycle?
  end

  test "explicit vllm backend maps to the recipe compose service" do
    backend = LongOcr::Backend.new(env: { "OCR_LONG_BACKEND" => "vllm" })

    assert backend.vllm?
    assert backend.manages_lifecycle?
    assert_equal "unlimited-ocr", backend.compose_service
    assert_equal "baidu/Unlimited-OCR", backend.model
  end

  test "auto falls back to the llama.cpp port without an NVIDIA GPU" do
    backend = LongOcr::Backend.new(env: { "OCR_LONG_BACKEND" => "auto", "OCR_LONG_FORCE_NVIDIA" => "0" })

    assert_equal :llamacpp, backend.name
    assert_equal "unlimited-ocr-llama", backend.compose_service
    assert backend.manages_lifecycle?
  end

  test "url override is honoured and trailing slash trimmed" do
    backend = LongOcr::Backend.new(env: {
      "OCR_LONG_BACKEND" => "llamacpp",
      "OCR_LONG_LLAMACPP_URL" => "http://host:8003/v1/"
    })

    assert_equal "http://host:8003/v1", backend.base_url
  end
end
