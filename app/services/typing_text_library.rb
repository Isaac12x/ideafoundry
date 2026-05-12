class TypingTextLibrary
  ENROLLMENT_TEXTS = {
    "early-workshop" => "every invention begins as a practical refusal to accept the obvious limit. the first model is usually rough, then the next model listens more carefully to friction, timing, materials, and the habits of the person who will use it. a good workshop keeps the question alive long enough for the useful shape to appear.",
    "patient-prototype" => "a patient prototype turns uncertainty into evidence. it lets an inventor notice which movement feels natural, which part bends too soon, and which assumption was only decoration. the breakthrough is rarely a single flash; it is a sequence of small corrections made visible by trying the thing again.",
    "useful-spark" => "the spark of an idea becomes an invention when it survives contact with real use. notes become sketches, sketches become mechanisms, and mechanisms become tools only after repeated tests reveal what should be simpler, stronger, quieter, or easier to repair."
  }.freeze

  UNLOCK_TEXTS = {
    "spark-gap" => "a useful invention crosses the small gap between a bright guess and a repeatable result.",
    "maker-table" => "on the maker table, every failed trial leaves a clearer mark for the next design.",
    "quiet-engine" => "the quiet engine of invention is careful observation repeated at the right moment.",
    "rough-model" => "a rough model can protect a fragile idea long enough for evidence to improve it."
  }.freeze

  class << self
    def enrollment_text(id)
      ENROLLMENT_TEXTS.fetch(id.to_s) { ENROLLMENT_TEXTS.values.first }
    end

    def unlock_text(id)
      UNLOCK_TEXTS.fetch(id.to_s) { UNLOCK_TEXTS.values.first }
    end

    def random_enrollment_id
      ENROLLMENT_TEXTS.keys.sample
    end

    def random_unlock_id
      UNLOCK_TEXTS.keys.sample
    end
  end
end
