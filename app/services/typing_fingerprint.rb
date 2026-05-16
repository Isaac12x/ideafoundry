class TypingFingerprint
  MIN_ENROLLMENT_SAMPLE_COUNT = 40
  MIN_UNLOCK_SAMPLE_COUNT = 24
  MIN_COMPARED_FEATURES = 8
  MATCH_THRESHOLD = 0.64

  HOLD_STDDEV_FLOOR = 38.0
  FLIGHT_STDDEV_FLOOR = 55.0
  MAX_Z_SCORE = 3.0

  Match = Struct.new(:score, :passed, :sample_count, :compared_features, keyword_init: true) do
    def passed?
      passed
    end
  end

  class << self
    def build(events:, expected_text:)
      normalized = normalize_events(events, expected_text)
      flights = flight_features(normalized)

      {
        "version" => 1,
        "sample_count" => normalized.size,
        "keys" => grouped_stats(normalized.map { |event| [event[:key], event[:hold]] }),
        "digraphs" => grouped_stats(flights.map { |flight| [flight[:digraph], flight[:latency]] }),
        "global" => {
          "hold" => stats(normalized.map { |event| event[:hold] }),
          "flight" => stats(flights.map { |flight| flight[:latency] })
        },
        "created_at" => Time.current.iso8601
      }
    end

    def match(template:, events:, expected_text:)
      sample = build(events:, expected_text:)
      similarities = []

      compare_group(template["keys"], sample["keys"], HOLD_STDDEV_FLOOR, similarities)
      compare_group(template["digraphs"], sample["digraphs"], FLIGHT_STDDEV_FLOOR, similarities)
      compare_stat(template.dig("global", "hold"), sample.dig("global", "hold"), HOLD_STDDEV_FLOOR, similarities, weight: 3)
      compare_stat(template.dig("global", "flight"), sample.dig("global", "flight"), FLIGHT_STDDEV_FLOOR, similarities, weight: 3)

      score = similarities.empty? ? 0.0 : similarities.sum / similarities.size
      passed = sample["sample_count"] >= MIN_UNLOCK_SAMPLE_COUNT &&
               similarities.size >= MIN_COMPARED_FEATURES &&
               score >= MATCH_THRESHOLD

      Match.new(
        score: score.round(3),
        passed: passed,
        sample_count: sample["sample_count"],
        compared_features: similarities.size
      )
    end

    private

    def normalize_events(events, expected_text)
      Array(events).filter_map do |event|
        index = event["index"].to_i
        key = event["key"].to_s
        expected_key = expected_text[index]
        down = event["down"].to_f
        up = event["up"].to_f
        hold = up - down

        next if expected_key.nil?
        next unless key == expected_key
        next unless hold.between?(20.0, 1_000.0)

        {
          key: canonical_key(key),
          index: index,
          down: down,
          up: up,
          hold: hold
        }
      end.sort_by { |event| event[:index] }
    end

    def canonical_key(key)
      key.match?(/[[:alpha:]]/) ? key.downcase : key
    end

    def flight_features(events)
      events.each_cons(2).filter_map do |left, right|
        next unless right[:index] == left[:index] + 1

        latency = right[:down] - left[:up]
        next unless latency.between?(-120.0, 1_200.0)

        {
          digraph: "#{left[:key]}#{right[:key]}",
          latency: latency
        }
      end
    end

    def grouped_stats(pairs)
      pairs.group_by(&:first).transform_values do |values|
        stats(values.map(&:last))
      end
    end

    def stats(values)
      values = values.compact.map(&:to_f)
      return { "mean" => 0.0, "stddev" => 0.0, "count" => 0 } if values.empty?

      mean = values.sum / values.size
      variance = values.sum { |value| (value - mean)**2 } / values.size

      {
        "mean" => mean.round(3),
        "stddev" => Math.sqrt(variance).round(3),
        "count" => values.size
      }
    end

    def compare_group(template_group, sample_group, stddev_floor, similarities)
      return if template_group.blank? || sample_group.blank?

      sample_group.each do |key, sample_stat|
        compare_stat(template_group[key], sample_stat, stddev_floor, similarities)
      end
    end

    def compare_stat(template_stat, sample_stat, stddev_floor, similarities, weight: 1)
      return if template_stat.blank? || sample_stat.blank?
      return if template_stat["count"].to_i.zero? || sample_stat["count"].to_i.zero?

      spread = [template_stat["stddev"].to_f, stddev_floor].max
      z_score = (sample_stat["mean"].to_f - template_stat["mean"].to_f).abs / spread
      similarity = 1.0 - ([z_score, MAX_Z_SCORE].min / MAX_Z_SCORE)

      weight.times { similarities << similarity }
    end
  end
end
