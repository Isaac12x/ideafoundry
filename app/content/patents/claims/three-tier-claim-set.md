---
title: "Three-tier claim set"
slug: three-tier-claim-set
cluster: claims
jurisdiction: US
aliases: ["tiered claims", "broad medium narrow claims"]
related: ["claim-tree", "independent-claim", "dependent-claim"]
sources: ["Patents - from defensive lawyering to strategic engineering..pdf"]
corrections: ["Source says to claim 'as abstractly as you can'; that conflicts with 101 and 112(a). Broad only within support and eligibility"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2106.html"]
---
A three-tier set layers claims by breadth so the patent has fallback positions:

1. **Broad**: the independent claim, fewest limits, aimed at the core inventive concept.
2. **Medium**: first-level dependents adding a specific technique or data type.
3. **Narrow**: deeper dependents with concrete implementation details, ideally with technical effects, that are most likely to survive prior art or 101 challenges.

Source caution: the source advises claiming "as abstractly as you can". Broad is good, but pure abstraction invites a 101 abstract-idea rejection and a lack of written-description support. For software, tie the broad claim to a technical process or device and make sure narrower tiers add technical specifics.

Example for QR verification: Tier 1 decode and compare; Tier 2 local reputation cache; Tier 3 cryptographic signature check with a stated latency mechanism.

Tip: ensure each tier is supported by the specification and anticipate amendments: moving a tier-3 limit into claim 1 narrows scope and can create prosecution history estoppel.

_Educational, not legal advice._
