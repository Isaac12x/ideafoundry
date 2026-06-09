class VoiceFingerprint
  CANONICAL_PHRASE = "By my will and power you will open. Open sesame".freeze
  SETUP_VARIANTS = [
    CANONICAL_PHRASE,
    "By my will and power, you will open. Open sesame!",
    "By my will and power you will open — open sesame."
  ].freeze
  MIN_ENROLLMENT_SAMPLE_COUNT = 3
  VERSION = 1

  class << self
    def build(samples:)
      normalized_samples = Array(samples).filter_map { |sample| normalize_sample(sample) }
      valid_samples = normalized_samples.select { |sample| canonical_phrase?(sample["transcript"]) }

      return empty_fingerprint(valid_samples.count) if valid_samples.count < MIN_ENROLLMENT_SAMPLE_COUNT

      durations = valid_samples.map { |sample| sample["duration_ms"].to_f }.select(&:positive?)
      volumes = valid_samples.map { |sample| sample["rms"].to_f }.select(&:positive?)

      {
        "version" => VERSION,
        "phrase" => CANONICAL_PHRASE,
        "normalized_phrase" => normalize_phrase(CANONICAL_PHRASE),
        "sample_count" => valid_samples.count,
        "average_duration_ms" => average(durations),
        "duration_tolerance_ms" => duration_tolerance(durations),
        "average_rms" => average(volumes),
        "rms_tolerance" => 0.25,
        "created_at" => Time.current.iso8601
      }.compact
    end

    def match?(template:, transcript:, sample: {})
      return false unless template.present?
      return false unless canonical_phrase?(transcript)
      return true unless sample.present?

      normalized_sample = normalize_sample(sample.merge("transcript" => transcript)) || {}
      duration_matches?(template, normalized_sample) && rms_matches?(template, normalized_sample)
    end

    def normalize_phrase(phrase)
      phrase.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def canonical_phrase?(phrase)
      normalize_phrase(phrase) == normalize_phrase(CANONICAL_PHRASE)
    end

    private

    def empty_fingerprint(sample_count)
      {
        "version" => VERSION,
        "phrase" => CANONICAL_PHRASE,
        "normalized_phrase" => normalize_phrase(CANONICAL_PHRASE),
        "sample_count" => sample_count
      }
    end

    def normalize_sample(sample)
      hash = sample.respond_to?(:to_unsafe_h) ? sample.to_unsafe_h : sample.to_h
      {
        "transcript" => hash["transcript"] || hash[:transcript],
        "duration_ms" => (hash["duration_ms"] || hash[:duration_ms]).to_f,
        "rms" => (hash["rms"] || hash[:rms]).to_f
      }
    rescue NoMethodError
      nil
    end

    def average(values)
      return nil if values.blank?

      values.sum / values.length
    end

    def duration_tolerance(values)
      return nil if values.blank?

      [values.max - values.min + 600, 1_200].max
    end

    def duration_matches?(template, sample)
      expected = template["average_duration_ms"].to_f
      actual = sample["duration_ms"].to_f
      return true unless expected.positive? && actual.positive?

      tolerance = template["duration_tolerance_ms"].to_f
      tolerance = 1_500 unless tolerance.positive?
      (actual - expected).abs <= tolerance
    end

    def rms_matches?(template, sample)
      expected = template["average_rms"].to_f
      actual = sample["rms"].to_f
      return true unless expected.positive? && actual.positive?

      tolerance = template["rms_tolerance"].to_f
      tolerance = 0.25 unless tolerance.positive?
      (actual - expected).abs <= tolerance
    end
  end
end
