require "test_helper"

class Kb::UrlImportSsrfTest < ActiveSupport::TestCase
  PAGE = "<html><head><title>Cold chain</title></head><body><article>#{'<p>Keep it at four degrees. </p>' * 40}</article></body></html>".freeze

  # Stands in for Net::HTTP.start's connection: answers each request_get from a queue of responses.
  FakeHttp = Struct.new(:res) do
    def request_get(*) = res
  end

  def response(klass, body: "", type: "text/html", location: nil)
    res = klass.new("1.1", "200", "")
    res.define_singleton_method(:content_type) { type }
    res.define_singleton_method(:[]) { |k| k.to_s.casecmp?("location") ? location : nil }
    res.define_singleton_method(:read_body) { |&blk| blk ? blk.call(body) : body }
    res
  end

  # dns: host => [ips]; responses served in order; records the connected addresses.
  def with_net(dns, responses)
    connected = []
    start = ->(host, _port, **opts, &blk) { connected << opts[:ipaddr]; blk.call(FakeHttp.new(responses.shift)) }
    Resolv.stub(:getaddresses, ->(host) { dns.fetch(host, []) }) do
      Net::HTTP.stub(:start, start) { yield }
    end
    connected
  end

  test "private, loopback and link-local hosts are refused, including names that resolve to them" do
    dns = { "evil.test" => [ "10.0.0.5" ], "meta.test" => [ "169.254.169.254" ], "lo.test" => [ "127.0.0.1" ] }
    with_net(dns, []) do
      %w[http://evil.test/ http://meta.test/latest http://lo.test/].each do |url|
        error = assert_raises(Kb::UrlImport::Error, url) { Kb::UrlImport.call(url) }
        assert_match(/private/, error.message)
      end
    end
  end

  test "a redirect to a private host is refused" do
    dns = { "ok.test" => [ "93.184.216.34" ], "internal.test" => [ "192.168.1.9" ] }
    responses = [ response(Net::HTTPFound, location: "http://internal.test/admin") ]
    connected = with_net(dns, responses) do
      error = assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("http://ok.test/") }
      assert_match(/private/, error.message)
    end
    assert_equal [ "93.184.216.34" ], connected # never connected to the private hop
  end

  test "a redirect to a non-http scheme is refused" do
    responses = [ response(Net::HTTPFound, location: "file:///etc/passwd") ]
    with_net({ "ok.test" => [ "93.184.216.34" ] }, responses) do
      assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("http://ok.test/") }
    end
    assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("gopher://ok.test/") }
  end

  test "redirect loops stop at the hop limit" do
    responses = Array.new(10) { response(Net::HTTPFound, location: "http://ok.test/again") }
    with_net({ "ok.test" => [ "93.184.216.34" ] }, responses) do
      assert_match(/Too many redirects/, assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("http://ok.test/") }.message)
    end
  end

  test "a non-HTML response is refused" do
    with_net({ "ok.test" => [ "93.184.216.34" ] }, [ response(Net::HTTPOK, body: "%PDF", type: "application/pdf") ]) do
      assert_match(/Not an HTML page/, assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("http://ok.test/x.pdf") }.message)
    end
  end

  test "the body is capped at MAX_BYTES" do
    huge = "<html><head><title>Big</title></head><body><p>#{'x' * (Kb::UrlImport::MAX_BYTES * 2)}</p></body></html>"
    got = nil
    with_net({ "ok.test" => [ "93.184.216.34" ] }, [ response(Net::HTTPOK, body: huge) ]) do
      html, = Kb::UrlImport.fetch("http://ok.test/")
      got = html
    end
    assert_operator got.bytesize, :<=, Kb::UrlImport::MAX_BYTES
  end

  test "a public page imports through the stubbed network" do
    with_net({ "ok.test" => [ "93.184.216.34" ] }, [ response(Net::HTTPOK, body: PAGE) ]) do
      assert_equal "Cold chain", Kb::UrlImport.call("http://ok.test/")["title"]
    end
  end

  test "the whole import has a deadline and reports it" do
    old = Kb::UrlImport::DEADLINE
    silence_warnings { Kb::UrlImport.const_set(:DEADLINE, 0.2) }
    Kb::UrlImport.stub(:fetch, ->(*) { sleep 2 }) do
      assert_match(/too long/, assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("http://ok.test/") }.message)
    end
  ensure
    silence_warnings { Kb::UrlImport.const_set(:DEADLINE, old) }
  end
end
