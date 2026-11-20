require "net/http"
require "resolv"
require "ipaddr"

module Kb
  # Pulls a web page into text at the moment of linking: {title, excerpt, url, host}. Only http(s), public hosts
  # (every redirect hop is re-checked), short timeouts, bounded body. The page is not kept, only the excerpt.
  module UrlImport
    class Error < StandardError; end

    MAX_BYTES = 2.megabytes
    MAX_HOPS = 4
    DEADLINE = 8 # seconds, whole import (DNS + every hop + body); it runs inside the request
    EXCERPT_CHARS = 1_500

    module_function

    def call(raw)
      url = Kb::UrlNormalizer.call(raw)
      html, final = Timeout.timeout(DEADLINE, Error, "The page took too long to answer.") { fetch(url) }
      page = Kb::WebPage.new(html, final)
      { "url" => final, "host" => page.host, "title" => page.title, "excerpt" => page.excerpt(EXCERPT_CHARS) }
    end

    def fetch(url, hops = 0)
      uri = parse!(url)
      raise Error, "Too many redirects." if hops > MAX_HOPS

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10,
                      ipaddr: resolve_public!(uri.host)) do |http|
        res = http.request_get(uri.request_uri, "User-Agent" => Kb::WebPage::UA, "Accept" => "text/html,application/xhtml+xml")
        case res
        when Net::HTTPRedirection then return fetch(URI.join(url, res["location"].to_s).to_s, hops + 1)
        when Net::HTTPSuccess
          raise Error, "Not an HTML page." unless res.content_type.to_s.match?(/html/i)

          [ read_capped(res), url ]
        else raise Error, "The page answered #{res.code}."
        end
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, EOFError => e
      raise Error, "Couldn't reach the page (#{e.class.name.demodulize})."
    end

    # Stops reading at MAX_BYTES instead of buffering the whole body.
    def read_capped(res)
      body = +""
      res.read_body do |chunk|
        body << chunk
        break if body.bytesize >= MAX_BYTES
      end
      body.byteslice(0, MAX_BYTES).to_s.scrub
    end

    def parse!(url)
      uri = URI.parse(url.to_s)
      raise Error, "Only http(s) links can be imported." unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri
    rescue URI::InvalidURIError
      raise Error, "That isn't a valid link."
    end

    # The vetted address is what we connect to (ipaddr:), so DNS can't flip to a private one after the check.
    def resolve_public!(host)
      ips = Resolv.getaddresses(host)
      raise Error, "Couldn't resolve #{host}." if ips.empty?
      raise Error, "That address is private." if ips.any? { |ip| private?(ip) }

      ips.first
    end

    def private?(ip)
      addr = IPAddr.new(ip)
      addr = addr.native if addr.ipv4_mapped?
      addr.private? || addr.loopback? || addr.link_local? || addr.to_s == "0.0.0.0" || addr.to_s == "::" ||
        (addr.ipv4? && IPAddr.new("100.64.0.0/10").include?(addr))
    end
  end
end
