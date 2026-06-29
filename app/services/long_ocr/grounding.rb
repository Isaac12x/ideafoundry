module LongOcr
  # Unwraps the grounding tokens Unlimited-OCR / DeepSeek-OCR emit into clean
  # markdown. Per the recipe: keep the text inside <|ref|>...<|/ref|> and drop
  # the <|det|>...<|/det|> coordinate boxes, then strip any remaining special
  # tokens (<image>, <|grounding|>, sentinels).
  module Grounding
    REF_OPEN = /<\|ref\|>/.freeze
    REF_CLOSE = %r{<\|/ref\|>}.freeze
    DET_BLOCK = %r{<\|det\|>.*?<\|/det\|>}m.freeze
    LEFTOVER_TOKEN = /<\|[^|]*\|>|<image>|<\/?s>/.freeze

    module_function

    def to_markdown(raw)
      text = raw.to_s
      return "" if text.strip.empty?

      text = text.gsub(DET_BLOCK, "")
      text = text.gsub(REF_OPEN, "").gsub(REF_CLOSE, "")
      text = text.gsub(LEFTOVER_TOKEN, "")
      normalize(text)
    end

    def normalize(text)
      lines = text.split("\n").map { |line| line.rstrip }
      # collapse 3+ blank lines to a single blank line
      out = []
      blanks = 0
      lines.each do |line|
        if line.strip.empty?
          blanks += 1
          out << "" if blanks == 1
        else
          blanks = 0
          out << line
        end
      end
      out.join("\n").strip
    end
  end
end
