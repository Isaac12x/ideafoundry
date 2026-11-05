require "test_helper"

class Kb::UrlNormalizerTest < ActiveSupport::TestCase
  def n(url) = Kb::UrlNormalizer.call(url)

  test "unwraps the suspended-tab example keeping the inner &t=" do
    raw = "chrome-extension://noogafoofpebimajpfpamcfhoaifemoa/suspended.html#ttl=(12)%20this%20method...&pos=0&uri=https://www.youtube.com/watch?v=ews_k4ikjuy&t=354s"
    assert_equal "https://www.youtube.com/watch?v=ews_k4ikjuy&t=354s", n(raw)
  end

  test "unwraps encoded nested urls in query, keeps ID case" do
    assert_equal "https://www.youtube.com/watch?v=AbC_dEf&t=5m54s",
                 n("chrome-extension://x/suspended.html?uri=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DAbC_dEf%26t%3D5m54s&pos=1")
  end

  test "unwraps known redirectors" do
    assert_equal "https://example.com/a?b=1", n("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1&sa=U&ved=2")
    assert_equal "https://example.com/x", n("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx&h=AT0")
    assert_equal "https://example.com/x", n("https://slack-redir.net/link?url=https%3A%2F%2Fexample.com%2Fx&v=3")
  end

  test "leaves ordinary and fully encoded urls alone" do
    assert_equal "https://example.com/search?q=https://other.com", n("https://example.com/search?q=https://other.com")
    assert_equal "https://youtu.be/AbC?t=9", n("  https://youtu.be/AbC?t=9 ")
    assert_equal "https://example.com/a?b=1", n("https%3A%2F%2Fexample.com%2Fa%3Fb%3D1")
    assert_equal "notes", n("notes")
  end

  test "KbDownload unwraps before the http check and derives the clip" do
    user = User.first || User.create!(email: "test@example.com", name: "Test")
    dl = KbDownload.new(user: user, source_index: 0, format: "auto", status: "pending",
                        url: "chrome-extension://x/suspended.html#uri=https://www.youtube.com/watch?v=ews_k4ikjuy&t=354s")
    assert dl.valid?
    assert_equal "https://www.youtube.com/watch?v=ews_k4ikjuy&t=354s", dl.url
    assert_equal [ 354, nil ], [ dl.clip_start, dl.clip_end ]
  end
end
