require "test_helper"

class TranscriptionsControllerTest < ActionDispatch::IntegrationTest
  Resp = Struct.new(:code, :body)

  def post_audio(content_type: "audio/wav", body: "RIFFfake")
    post transcriptions_url, params: body, headers: { "CONTENT_TYPE" => content_type }
  end

  def with_upstream(result, &block)
    fake = ->(*_args, **_opts, &_blk) { result.respond_to?(:call) ? result.call : result }
    Net::HTTP.stub(:start, fake, &block)
  end

  test "returns the enhanced text" do
    with_upstream(Resp.new("200", { text: "raw words", enhancedText: " Clean words. " }.to_json)) { post_audio }

    assert_response :success
    assert_equal "Clean words.", response.parsed_body["text"]
  end

  test "falls back to raw text without enhancement" do
    with_upstream(Resp.new("200", { text: "raw words", enhancementError: "mlx down" }.to_json)) { post_audio }

    assert_equal "raw words", response.parsed_body["text"]
  end

  test "offline service is 503" do
    with_upstream(-> { raise Errno::ECONNREFUSED }) { post_audio }

    assert_response :service_unavailable
    assert_equal "Voice service offline", response.parsed_body["error"]
  end

  test "too short upstream is 422" do
    with_upstream(Resp.new("422", "{}")) { post_audio }

    assert_response :unprocessable_content
  end

  test "rejects unsupported content type" do
    post_audio(content_type: "audio/webm")

    assert_response :unsupported_media_type
  end

  test "locked workspace rejects the request" do
    User.first.update!(settings: { "typing_lock" => { "enabled" => true } })
    post_audio

    assert_response :redirect
  end
end
