require "test_helper"

class MediaDigestTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @dl = @user.kb_downloads.create!(source_index: 0, url: "https://youtu.be/abc", title: "Rails Talk", status: "done")
  end

  def record(body, pipeline = "transcript_v1")
    MediaDigest.record!(user: @user, kb_download: @dl, body: body, pipeline: pipeline)
  end

  test "newer digest supersedes older current one" do
    old = record("- old fact")
    new = record("- new fact")
    assert_equal [ new ], MediaDigest.current.to_a
    assert_equal new.id, old.reload.superseded_by_id
    assert old.superseded_at
  end

  test "lower ranked pipeline does not supersede higher" do
    av = record("- av fact", "av_v1")
    low = record("- transcript fact")
    assert_equal [ av ], MediaDigest.current.to_a
    assert_equal av.id, low.reload.superseded_by_id
  end

  test "validates pipeline and body" do
    assert_not MediaDigest.new(user: @user, kb_download: @dl, pipeline: "x", body: "").valid?
  end

  test "search ranks by matching terms and ignores superseded" do
    other = @user.kb_downloads.create!(source_index: 0, url: "https://youtu.be/def", title: "Cooking", status: "done")
    MediaDigest.record!(user: @user, kb_download: other, body: "sourdough old")
    MediaDigest.record!(user: @user, kb_download: other, body: "sourdough only")
    record("sourdough starter hydration")
    assert_equal [ "sourdough starter hydration", "sourdough only" ], MediaDigest.search("sourdough starter hydration").map(&:body)
    assert_equal [ "sourdough starter hydration" ], MediaDigest.search("hydration").map(&:body)
    assert_equal 2, MediaDigest.search("rails sourdough").size # title match on Rails Talk
  end

  test "search escapes LIKE wildcards" do
    record("- 100% reliable")
    assert_empty MediaDigest.search("zzz%")
    assert_equal 1, MediaDigest.search("100%").size
    assert_empty MediaDigest.search("a_")
  end
end
