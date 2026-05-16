require "test_helper"

class TypingFingerprintTest < ActiveSupport::TestCase
  SAMPLE_TEXT = "inventors refine rough machines into useful systems, then repeat the small experiment again."

  test "build stores statistical typing template without raw events" do
    template = TypingFingerprint.build(events: timing_events_for(SAMPLE_TEXT), expected_text: SAMPLE_TEXT)

    assert_equal 1, template["version"]
    assert_operator template["sample_count"], :>, 40
    assert_includes template["keys"], "i"
    assert_includes template["digraphs"], "in"
    assert_nil template["events"]
  end

  test "match accepts similar timing and rejects distant timing" do
    template = TypingFingerprint.build(events: timing_events_for(SAMPLE_TEXT, hold: 90, flight: 44), expected_text: SAMPLE_TEXT)

    similar = TypingFingerprint.match(
      template: template,
      events: timing_events_for(SAMPLE_TEXT, hold: 96, flight: 50),
      expected_text: SAMPLE_TEXT
    )
    distant = TypingFingerprint.match(
      template: template,
      events: timing_events_for(SAMPLE_TEXT, hold: 215, flight: 170),
      expected_text: SAMPLE_TEXT
    )

    assert similar.passed?, "expected similar sample to pass with score #{similar.score}"
    refute distant.passed?, "expected distant sample to fail with score #{distant.score}"
  end

  private

  def timing_events_for(text, hold: 88, flight: 42)
    time = 1000.0

    text.chars.each_with_index.map do |key, index|
      duration = hold + (index % 5)
      event = {
        "key" => key,
        "index" => index,
        "down" => time,
        "up" => time + duration
      }
      time += duration + flight + (index % 3)
      event
    end
  end
end
