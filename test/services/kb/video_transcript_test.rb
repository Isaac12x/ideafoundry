require "test_helper"

class Kb::VideoTranscriptTest < ActiveSupport::TestCase
  def ev(start_ms, dur_ms, text) = { tStartMs: start_ms, dDurationMs: dur_ms, segs: [ { utf8: text } ] }

  test "chunks entries into 90s MM:SS lines, skipping empty events" do
    json = { events: [
      { tStartMs: 0, dDurationMs: 1000 },
      ev(0, 40_000, "Hello\nthere"),
      ev(40_000, 50_000, " world "),    # 40 + 50 = 90, still fits
      ev(90_000, 1_000, "  "),          # blank, skipped
      ev(90_000, 30_000, "next"),       # 90 + 30 > 90 -> new chunk
      ev(125_000, 10_000, "end")
    ] }.to_json

    assert_equal "00:00 - Hello there world\n01:30 - next end\n", Kb::VideoTranscript.render(json)
  end

  test "render is nil without any text" do
    assert_nil Kb::VideoTranscript.render({ events: [ { tStartMs: 0 } ] }.to_json)
  end

  test "parses rolling VTT: tags, entities, header blocks and repeated lines" do
    vtt = <<~VTT
      WEBVTT
      Kind: captions

      NOTE ignore me

      00:00:00.000 --> 00:00:02.000 align:start position:0%
      Hello <c>there</c>

      00:00:02.000 --> 00:00:04.000
      Hello <c>there</c>
      <00:00:03.000><c>you &amp; me</c>

      00:00:04.000 --> 00:00:06.000
      you &amp; me
      bye
    VTT

    assert_equal [
      { start: 0.0, duration: 2.0, text: "Hello there" },
      { start: 2.0, duration: 2.0, text: "you & me" },
      { start: 4.0, duration: 2.0, text: "bye" }
    ], Kb::VideoTranscript.parse_cues(vtt)
    assert_equal "00:00 - Hello there you & me bye\n", Kb::VideoTranscript.render(vtt, "vtt")
  end

  test "parses SRT with comma timings and short MM:SS timings" do
    srt = "1\n00:01:30,500 --> 00:01:32,000\nfirst\n\n2\n01:33.000 --> 01:35.500\nsecond\n"

    assert_equal [ { start: 90.5, duration: 1.5, text: "first" }, { start: 93.0, duration: 2.5, text: "second" } ],
                 Kb::VideoTranscript.parse_cues(srt)
    assert_equal "01:30 - first second\n", Kb::VideoTranscript.render(srt, "srt")
  end
end
