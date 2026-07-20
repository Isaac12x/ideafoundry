require "test_helper"

class LongOcrGroundingTest < ActiveSupport::TestCase
  test "keeps ref text, drops det boxes and stray special tokens" do
    raw = "<image>\n<|ref|>Hello world<|/ref|><|det|>[[12, 8, 40, 22]]<|/det|>\n<|grounding|></s>"
    assert_equal "Hello world", LongOcr::Grounding.to_markdown(raw)
  end

  test "preserves markdown structure across lines and collapses blank runs" do
    raw = "# Title\n\n\n\n<|ref|>Body paragraph<|/ref|><|det|>[[0,0,1,1]]<|/det|>"
    result = LongOcr::Grounding.to_markdown(raw)

    assert_equal "# Title\n\nBody paragraph", result
  end

  test "blank input yields empty string" do
    assert_equal "", LongOcr::Grounding.to_markdown("   \n  ")
    assert_equal "", LongOcr::Grounding.to_markdown(nil)
  end
end
