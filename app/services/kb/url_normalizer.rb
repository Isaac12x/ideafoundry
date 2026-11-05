# One intake normalizer for every "paste a link" path: digs the real http(s) URL
# out of wrapper links (suspended-tab pages, Google/Facebook/Slack redirectors,
# fully percent-encoded URLs). Anything else comes back untouched (stripped).
# Never changes case: video IDs are case-sensitive.
module Kb
  module UrlNormalizer
    KEYS = %w[uri url u target q uddg].freeze
    # http(s) hosts known to wrap outbound links; other http(s) pages keep their ?q=/?url= params.
    REDIRECTORS = /\A(?:www\.|l\.|lm\.|m\.)?(?:google\.[a-z.]+|facebook\.com|slack-redir\.net|youtube\.com|linkedin\.com|out\.reddit\.com|duckduckgo\.com)\z/i
    PARAM = /[?&#](?:#{KEYS.join("|")})=(?=https?(?::\/\/|%3A))/i
    MAX_DEPTH = 5

    def self.call(raw)
      url = raw.to_s.strip
      MAX_DEPTH.times do
        inner = unwrap_once(url)
        break if inner.nil? || inner == url
        url = inner
      end
      url
    end

    def self.unwrap_once(url)
      return CGI.unescape(url) if url.match?(/\Ahttps?%3A%2F%2F/i)
      return unless wrapper?(url) && (m = url.match(PARAM))

      rest = m.post_match
      # Encoded value ends at the next "&"; a literal one owns the rest (its own &t=354s).
      rest.match?(/\Ahttps?%3A/i) ? CGI.unescape(rest[/\A[^&#]*/]) : rest
    end

    def self.wrapper?(url)
      return true unless url.match?(/\Ahttps?:\/\//i)
      url[%r{\Ahttps?://([^/?#:]+)}i, 1].to_s.match?(REDIRECTORS)
    end
  end
end
