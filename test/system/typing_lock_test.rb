require "application_system_test_case"

class TypingLockTest < ApplicationSystemTestCase
  test "failed unlock stays on score page with decoy text" do
    user = users(:one)
    user.update!(settings: { "typing_lock" => { "enabled" => true } })

    unlock_text = TypingTextLibrary.unlock_text("spark-gap")
    user.store_typing_fingerprint!(fingerprint_for(unlock_text, hold: 340, flight: 260))

    visit typing_lock_path(challenge_id: "spark-gap", return_to: ideas_path)

    assert_text "Typing rhythm score"
    assert_no_text "Locked"

    input = find("textarea.typing-lock-input")
    input.click
    unlock_text.each_char { |char| input.send_keys(char) }

    assert_text "This is your score", wait: 5
    assert_selector ".typing-lock-form"
    assert_no_text "Fingerprint not matched"
    assert_current_path %r{/typing-lock}
  end

  private

  def fingerprint_for(text, hold:, flight:)
    TypingFingerprint.build(events: timing_events_for(text, hold:, flight:), expected_text: text)
  end

  def timing_events_for(text, hold:, flight:)
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
