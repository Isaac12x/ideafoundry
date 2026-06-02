class TypingTextLibrary
  ENROLLMENT_TEXTS = {
    "early-workshop" => "every invention begins as a practical refusal to accept the obvious limit. the first model is usually rough, then the next model listens more carefully to friction, timing, materials, and the habits of the person who will use it. a good workshop keeps the question alive long enough for the useful shape to appear.",
    "patient-prototype" => "a patient prototype turns uncertainty into evidence. it lets an inventor notice which movement feels natural, which part bends too soon, and which assumption was only decoration. the breakthrough is rarely a single flash; it is a sequence of small corrections made visible by trying the thing again.",
    "useful-spark" => "the spark of an idea becomes an invention when it survives contact with real use. notes become sketches, sketches become mechanisms, and mechanisms become tools only after repeated tests reveal what should be simpler, stronger, quieter, or easier to repair.",
    "honest-material" => "the material always has an opinion. a careful inventor learns to read the grain of wood, the memory of metal, and the resistance of glass before asking any of them to do something new. the design that respects its material tends to outlast the one that fights it.",
    "second-draft" => "most inventions look inevitable only in hindsight. the first draft solves a problem that the inventor understood poorly. the second draft solves the problem that emerged from building the first. by the third, the inventor has stopped guessing and started listening to what the thing itself wants to become.",
    "field-notes" => "a notebook kept close to the bench is worth more than a report written later from memory. the exact weight of a failed part, the unexpected sound a joint makes under load, the moment a tolerance shifts with temperature — these are the details that turn a promising idea into a reliable one."
  }.freeze

  UNLOCK_TEXTS = {
    "spark-gap" => "a useful invention crosses the small gap between a bright guess and a repeatable result.",
    "maker-table" => "on the maker table, every failed trial leaves a clearer mark for the next design.",
    "quiet-engine" => "the quiet engine of invention is careful observation repeated at the right moment.",
    "rough-model" => "a rough model can protect a fragile idea long enough for evidence to improve it.",
    "honest-measure" => "an inventor who measures twice before cutting once earns the right to cut with confidence.",
    "borrowed-tool" => "every new tool is borrowed from a problem that refused to be ignored.",
    "close-tolerance" => "a close tolerance is a promise between the designer and the material.",
    "second-attempt" => "the second attempt carries the weight of everything the first attempt taught.",
    "worn-bench" => "a worn bench is the signature of someone who kept working until the thing was right.",
    "field-fix" => "the best invention is sometimes the one improvised far from the workshop with whatever is at hand.",
    "brass-hinge" => "a brass hinge remembers every careless shortcut, so the careful maker listens before tightening the final screw.",
    "paper-circuit" => "a paper circuit can prove the shape of an idea before copper, code, or glass enter the room.",
    "calm-lever" => "a calm lever does not need to look dramatic when it moves the right weight at the right time.",
    "glass-gauge" => "the glass gauge tells the truth quietly, even when the inventor hoped the pressure would stay hidden.",
    "bench-lamp" => "under the bench lamp, a difficult part becomes less mysterious with every patient adjustment.",
    "threaded-needle" => "a threaded needle turns loose fabric into a useful seam only after the hand learns the pattern.",
    "north-magnet" => "the north magnet pulls scattered filings into order, the way a good question pulls a design into focus.",
    "clock-spring" => "a clock spring stores yesterday's winding so tomorrow's mechanism can move without complaint.",
    "inked-template" => "an inked template saves the hand from guessing and gives the next cut a cleaner beginning.",
    "small-furnace" => "a small furnace teaches patience because the metal changes only when heat, time, and attention agree.",
    "steady-gear" => "a steady gear makes progress visible one tooth at a time, even when the whole machine turns slowly.",
    "oiled-runner" => "an oiled runner reveals whether the design was truly smooth or merely quiet while no one was testing it.",
    "folded-map" => "a folded map is still useful if the maker knows which crease points back to the unsolved problem.",
    "bright-filament" => "a bright filament is only useful when the rest of the circuit is honest enough to carry the load.",
    "clean-join" => "a clean join disappears into the object, leaving only the feeling that the whole thing belongs together.",
    "test-weight" => "a test weight does not argue with optimism; it simply shows what the frame can actually hold."
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
