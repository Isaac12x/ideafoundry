require "test_helper"

class Kb::ClipTimeTest < ActiveSupport::TestCase
  test "parses seconds, units and clock forms" do
    { "354" => 354, "354s" => 354, "5m54s" => 354, "1h2m3s" => 3723, "5:54" => 354, "1:02:03" => 3723, "npt:10" => 10, "12.7" => 12 }.each do |input, sec|
      assert_equal sec, Kb::ClipTime.parse(input), input
    end
    [ nil, "", "abc", "1:2:3:4", "5m x" ].each { |bad| assert_nil Kb::ClipTime.parse(bad), bad.inspect }
  end

  test "from_url reads t, start, end and media fragments" do
    assert_equal [ 354, nil ], Kb::ClipTime.from_url("https://www.youtube.com/watch?v=x&t=354s")
    assert_equal [ 354, nil ], Kb::ClipTime.from_url("https://www.youtube.com/watch?v=x&t=5m54s")
    assert_equal [ 3723, nil ], Kb::ClipTime.from_url("https://youtu.be/x?t=1h2m3s")
    assert_equal [ 10, 70 ], Kb::ClipTime.from_url("https://www.youtube.com/embed/x?start=10&end=70")
    assert_equal [ 5, 9 ], Kb::ClipTime.from_url("https://example.com/v.mp4#t=5,9")
    assert_equal [ 90, nil ], Kb::ClipTime.from_url("https://vimeo.com/1#t=1m30s")
    assert_equal [ nil, nil ], Kb::ClipTime.from_url("https://example.com/v")
  end

  test "formats" do
    assert_equal "5:54", Kb::ClipTime.format(354)
    assert_equal "1:02:03", Kb::ClipTime.format(3723)
    assert_equal "5m54s", Kb::ClipTime.slug(354)
    assert_equal "1h2m3s", Kb::ClipTime.slug(3723)
    assert_equal "*354-430", Kb::ClipTime.section(354, 430)
    assert_equal "*354-inf", Kb::ClipTime.section(354, nil)
  end
end
