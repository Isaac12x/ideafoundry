---
title: Element matrix
slug: element-matrix
cluster: prior-art
jurisdiction: US
aliases: [claim chart, element comparison table, reference breakdown]
related: [novelty-102, obviousness-103, prior-art-search, build-around-tactics, search-log, argue-vs-amend]
sources: ["Patents How to analyze prior art.pdf", "Patents - litmus test.pdf"]
corrections: ["Source treats an empty cell ('not suggested') as the novelty story; absence from your matrix is a lead, not proof of non-obviousness, since an examiner may add references or rely on common sense (KSR)"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2141.html"]
---
An element matrix compares each claim limitation against each reference, one row per element and one column per reference. It turns a pile of search hits into a map of what is old and what may be new.

Build it:
1. Break your draft claim into limitations.
2. For each reference, mark present, absent, or partly, and cite the passage or figure.
3. Note whether elements appear together in one reference (102 risk) or across several (103 risk).
4. Check arrangement and order, not just presence.

Example (illustrative):
| Element | Ref A | Ref B |
| image capture | yes | no |
| URL decoding | yes | no |
| reputation check before launch | no | partly (after launch) |
| offline cache | no | no |

Reading it: the combined A+B still lacks the pre-launch timing and the offline cache. Those are candidate features for claim amendments or dependents, subject to support in the specification.

The same table serves the 102 response chart: claim limitation, examiner's cited passage, your analysis. Keep entries factual and quote the reference.

_Educational, not legal advice._
