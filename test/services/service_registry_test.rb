require "test_helper"
require "socket"

class ServiceRegistryTest < ActiveSupport::TestCase
  setup { @orig = ENV.delete("SEMANTIC_SERVICE_URL") }
  teardown { ENV["SEMANTIC_SERVICE_URL"] = @orig if @orig }

  test "blank url is off" do
    r = ServiceRegistry.test("semantic")
    assert_equal [ false, "off" ], [ r[:ok], r[:status] ]
  end

  test "non-http scheme is rejected" do
    r = ServiceRegistry.test("semantic", "SEMANTIC_SERVICE_URL" => "file:///etc/passwd")
    assert_equal "error", r[:status]
    assert_equal "only http(s) URLs", r[:detail]
  end

  test "connection refused is an error" do
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    r = ServiceRegistry.test("semantic", "SEMANTIC_SERVICE_URL" => "http://127.0.0.1:#{port}")
    assert_equal "error", r[:status]
    assert_kind_of Integer, r[:ms]
  end

  test "healthy http service is ok and /extract is stripped" do
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      c = server.accept
      @request = c.gets
      c.write "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
      c.close
    end
    r = ServiceRegistry.test("ocr", "OCR_SERVICE_URL" => "http://127.0.0.1:#{server.addr[1]}/extract")
    thread.join
    assert r[:ok], r[:detail]
    assert_match %r{GET /health }, @request
  ensure
    server&.close
  end

  test "bin found and missing" do
    ok = ServiceRegistry.test("ebook_convert", "EBOOK_CONVERT_BIN" => "/bin/echo")
    assert ok[:ok], ok[:detail]
    miss = ServiceRegistry.test("ddjvu", "DDJVU_BIN" => "/nonexistent/definitely-not-here")
    assert_equal "error", miss[:status]
  end

  test "view_model reports value, override and source" do
    ServiceSetting.create!(key: "WHISPER_MODEL", value: "small")
    f = ServiceRegistry.view_model.find { |s| s[:key] == "whisper" }[:fields].find { |x| x[:env] == "WHISPER_MODEL" }
    assert_equal [ "small", "small", "settings" ], [ f[:value], f[:override], f[:source] ]
  end
end
