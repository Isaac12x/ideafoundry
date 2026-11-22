---
title: "Worked example: QR URL verification"
slug: example-qr-url-verification
cluster: workflows
jurisdiction: US
aliases: [QR code example, worked application example, example application]
related: [three-tier-claim-set, alice-two-step, technical-improvement-eligibility, claim-categories, beauregard-claim, technical-effect-paragraph, minimum-figure-set, specification-structure, antecedent-basis, argument-archetypes]
sources: ["Patents.pdf", "Patents - software patents.pdf", "Patents - from defensive lawyering to strategic engineering..pdf", "Patents - provisional claims and provisional claims to non-provisional patent tree .pdf"]
corrections: ["Source claim 1 (decode QR, analyze URL against a database) is a textbook Alice risk; rewritten with a concrete technical improvement", "Source mixes a hash match with a score threshold; separated into a deterministic stage and a scoring stage", "Source invented numbers (latency, percentages, prior-art names) are labelled illustrative"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2106.html", "https://www.uspto.gov/web/offices/pac/mpep/s608.html"]
---
Illustrative only: every number, name and application number below is invented for teaching (for example "Application No. XX/XXX,XXX", "under 50 ms").

Idea: a phone camera app checks a scanned QR URL before the browser opens it.

Technical problem: a network round trip delays the check, and a failed lookup leaves the user either blocked or unprotected.

Solution: two stages. Stage 1 is deterministic: a hash of the normalized URL is tested against a compact on-device blocklist filter, no network. Stage 2 runs only if stage 1 is inconclusive: a server returns a reputation score, compared with a threshold. Hash match and score threshold are different tests; never one clause.

Claim 1 (method, Alice-aware):
1. A method performed by a mobile device, comprising: capturing, by a camera, an image containing a QR code; decoding a payload into a URL; normalizing the URL into a canonical form; computing a hash of the canonical form; testing the hash against a filter stored in device memory to produce a match or no-match result; when no-match, transmitting a hash prefix to a server and receiving a score, and comparing the score to a threshold; and withholding the URL from a browser launch call until a verdict is produced, wherein the filter test completes without network access.

Claim 2: filter is a probabilistic set. Claim 3: prefix length limited so the server cannot recover the URL.
Claim 10 (system): processor, camera, memory storing the filter, instructions performing claim 1 steps.
Claim 18 (CRM): non-transitory medium storing instructions performing the same steps.

Why it is better than the source: the improvement (fast local check, privacy-preserving lookup) is in the claim, not just "analyze URL against database".

Figures (illustrative list): FIG. 1 system; FIG. 2 flowchart of two stages; FIG. 3 filter and hash prefix data layout; FIG. 4 verdict UI.

Spec outline: field; neutral background; summary mirroring claims; figure descriptions; detailed description with alternatives (other filters, offline-only, cached scores); technical-effect paragraph (e.g. "under 50 ms" as an example, never presented as measured unless it was).

Risk: claims still face eligibility and obviousness review.

_Educational, not legal advice._
