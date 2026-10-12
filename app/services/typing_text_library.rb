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
    "ford-real-task" => "hard thought and hard work move a business forward when slogans cannot.",
    "ford-better-ways" => "a useful maker keeps finding new and better ways for the product to serve.",
    "ford-precision" => "precision grows when better machinery and better habits pull each tolerance closer.",
    "feynman-question" => "there is no learning without a question, and every honest question leaves room for doubt.",
    "feynman-uncertainty" => "it is more interesting to live with uncertainty than to hold answers that might be wrong.",
    "feynman-evidence" => "experience teaches the lesson, and science asks how the evidence was found.",
    "rines-free-minds" => "a dynamic society depends on free creative minds and the protected fruits of their work.",
    "rines-conformity" => "conformity is the enemy of innovation when organizations stop listening to original thought.",
    "rines-create" => "when obstacles choke creativity, the only useful course is to create before time runs out.",
    "test-weight" => "a test weight does not argue with optimism; it simply shows what the frame can actually hold.",
    "problem-definition" => "A good invention begins by understanding the problem clearly enough that you know exactly what needs to change.",
    "right-problem" => "Solving the wrong problem brilliantly is still less valuable than identifying the right problem in the first place.",
    "problem-reframing" => "When a problem seems impossible, changing the way you describe it can expose entirely different solutions.",
    "hidden-obvious" => "Many important inventions come from noticing needs that have become so familiar that everyone else has stopped seeing them.",
    "need-finding" => "Inventors should look for persistent frustrations, compromises, and awkward workarounds because they often reveal unmet needs.",
    "naive-confidence" => "Not knowing all the reasons something supposedly cannot be done can sometimes make it easier to imagine that it can.",
    "vision-building" => "An inventor needs a sufficiently clear picture of the desired outcome before the details of implementation are known.",
    "paradigm-awareness" => "Existing assumptions define what people consider possible, so recognizing those assumptions is often the first step toward escaping them.",
    "relaxed-attention" => "Creative observations are more likely when the mind is attentive without being narrowly fixated on finding an answer.",
    "creative-observation" => "Ordinary objects and everyday experiences can reveal extraordinary ideas when examined from an unfamiliar perspective.",
    "mental-feeding" => "Creativity depends partly on giving the brain enough technical knowledge, experiences, observations, and examples to recombine.",
    "subconscious-work" => "A difficult problem can continue being processed outside conscious attention even when you appear to have stopped working on it.",
    "intuitive-judgment" => "Intuition often represents accumulated experience being processed faster than conscious reasoning can explain it.",
    "inner-senses" => "Inventors can mentally feel, visualize, or manipulate an idea before they are capable of describing it precisely.",
    "idea-percolation" => "Some ideas improve when they are allowed to develop gradually instead of being forced immediately into a final solution.",
    "emotional-distance" => "Falling in love with an idea can prevent you from noticing evidence that the idea is wrong.",
    "active-thinking" => "Building, sketching, experimenting, and manipulating things can generate insights that thinking alone may never produce.",
    "inspiration-flash" => "A sudden insight usually appears instantaneous only because much of the intellectual work happened beforehand.",
    "idea-resonance" => "Promising ideas often have an internal coherence in which many pieces of the problem suddenly begin fitting together.",
    "life-experience" => "Knowledge acquired in one area of life can become the unexpected solution to a problem encountered somewhere else.",
    "familiar-renewal" => "Innovation can come from taking something familiar and reconsidering what it could do rather than accepting what it currently does.",
    "physical-principles" => "Understanding fundamental physical principles gives inventors building blocks that can be recombined into entirely new mechanisms.",
    "chance-discovery" => "Accidents become inventions only when someone recognizes that an unexpected result has significance.",
    "natural-models" => "Nature provides mechanisms, structures, feedback systems, and strategies that inventors can reinterpret for human problems.",
    "multiple-processes" => "There is no single sequence that produces every invention; different problems demand different paths toward discovery.",
    "simple-design" => "The strongest solution is often the one that accomplishes its purpose with the fewest unnecessary parts and assumptions.",
    "essential-function" => "Removing everything that does not contribute meaningfully to the central function can expose the true invention underneath.",
    "complexity-control" => "Complexity should be accepted only when the additional complexity produces enough additional value to justify itself.",
    "zero-mass" => "An especially powerful design improvement is sometimes achieved by eliminating a component instead of improving it.",
    "elegant-design" => "Elegance appears when a solution performs a difficult task through an unexpectedly economical arrangement.",
    "resource-efficiency" => "A clever invention extracts as much useful function as possible from as little material, energy, information, or machinery as possible.",
    "core-inventions" => "Some inventions become powerful because they provide a fundamental mechanism that can support countless later applications.",
    "adaptive-systems" => "A design becomes more capable when it can respond automatically to changing conditions instead of requiring continuous external adjustment.",
    "smart-systems" => "The best response to variation is sometimes to design the variation into the system rather than attempting to eliminate it.",
    "elegant-constraints" => "Constraints can improve invention by forcing the designer to search for solutions that use available resources more intelligently.",
    "robust-design" => "A useful invention must continue performing its essential purpose despite imperfect conditions, variation, misuse, and unexpected events.",
    "structural-strength" => "Robustness begins by ensuring that the basic structure can tolerate the stresses it is realistically likely to encounter.",
    "useful-redundancy" => "Duplication is worthwhile when the failure of one element would otherwise destroy the entire function of the invention.",
    "failure-tolerance" => "A strong design assumes that individual components will eventually fail and prevents those failures from becoming catastrophic.",
    "self-healing" => "The most robust systems can detect certain failures and compensate for them without requiring immediate external intervention.",
    "managed-failure" => "Sometimes the correct objective is not preventing every failure but controlling how the system behaves when failure inevitably occurs.",
    "iterative-testing" => "An invention usually becomes workable through repeated cycles of building, observing, correcting, and rebuilding.",
    "component-testing" => "Complex inventions should first be tested as individual subsystems so that failures can be isolated and understood.",
    "system-testing" => "Components that work perfectly in isolation may behave differently when connected, making integrated testing essential.",
    "progressive-complexity" => "Testing should begin with simple controlled conditions and gradually introduce the complexity of the real environment.",
    "mistake-recognition" => "Inventive skill includes becoming good at recognizing when your own assumptions or solutions are wrong.",
    "approach-change" => "Persistence does not mean endlessly defending one solution; sometimes progress requires abandoning the approach and starting differently.",
    "prototype-learning" => "A prototype is valuable not merely because it demonstrates an idea but because it reveals things that the inventor did not know to ask.",
    "practical-reality" => "An invention becomes meaningful only when the conceptual idea can survive contact with materials, manufacturing, cost, users, and the physical world.",
    "inventive-discipline" => "Invention combines imagination with disciplined observation, experimentation, criticism, iteration, and the willingness to keep refining an idea until it works."
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

    def unlock_id?(id)
      UNLOCK_TEXTS.key?(id.to_s)
    end

    # Never repeats the previous prompt so each lock screen rotates.
    def random_unlock_id(except: nil)
      ids = UNLOCK_TEXTS.keys
      (ids - [ except.to_s ]).sample || ids.sample
    end
  end
end
