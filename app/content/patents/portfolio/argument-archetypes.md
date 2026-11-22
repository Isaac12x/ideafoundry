---
title: Argument archetypes
slug: argument-archetypes
cluster: portfolio
jurisdiction: US
aliases: [pre-armed drafting, argument tree, seeded arguments]
related: [three-tier-claim-set, argue-vs-amend, teach-away, unexpected-results, ids-duty-of-candor, technical-effect-paragraph, ksr]
sources: ["Patents - from defensive lawyering to strategic engineering..pdf"]
corrections: ["Source's example of an invented 'surprisingly 40%' result must not be written as fact; only true, supported statements belong in a spec or response"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2145.html", "https://www.uspto.gov/web/offices/pac/mpep/s2106.html"]
---
Idea: while drafting, plant truthful statements and fallback claim branches you can later rely on against likely rejections.

Common archetypes (claim branches plus supporting text):
- Timing/sequence: order of operations matters.
- Architecture: where each component runs.
- Data handling: format, caching, normalization.
- Hardware configuration: concrete device elements.
- Performance effect: measured technical improvement.

Seeding steps:
1. List likely rejections (anticipation, obviousness, eligibility).
2. For each, write the spec statement that supports the best response: why prior art doesn't suggest the combination, problem solved, structural difference.
3. Add a dependent claim for each branch.
4. Keep only what is true. Invented or unsupported data in a spec can fail enablement or support unenforceability allegations; later submissions are bound by candor duties.

Caveat: "different problem" arguments are weaker after KSR; a known problem can still motivate a combination.

Example: dependent claims on a local filter (architecture) and a latency budget (performance), each backed by a measured paragraph.

_Educational, not legal advice._
