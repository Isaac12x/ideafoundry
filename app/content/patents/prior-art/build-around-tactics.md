---
title: Building around prior art
slug: build-around-tactics
cluster: prior-art
jurisdiction: US
aliases: [draft around prior art, claim differentiation tactics]
related: [element-matrix, obviousness-103, novelty-102, ksr, unexpected-results, patent-eligibility-101, claim-categories, technical-effect-paragraph]
sources: ["Patents How to analyze prior art.pdf"]
corrections: ["'Change the claim category' does not avoid anticipation by the same disclosure", "'Reframe the problem' is weak after KSR", "A device claim written 'per claim 1' referencing a method claim is improper form; write it as its own independent claim", "Source says you cannot say 'non-obvious' in the specification; you can and should state real technical advantages, but not argue legal conclusions or invent results"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2143.html", "https://www.uspto.gov/web/offices/pac/mpep/s608.html"]
---
Drafting around prior art means claiming what is genuinely different and technically meaningful, supported by the specification.

Tactics that help:
- **Real technical difference**: new structure, sequence, timing, or data flow that the art lacks (for example check a URL before launching it).
- **Technical advantage**: explain why the difference matters, in true, supportable terms.
- **Layered fallbacks**: dependent claims with narrower features (offline cache, model inputs) so amendments are ready.
- **Multiple categories**: method, system, and medium claims widen coverage, but each must still be new and non-obvious over the art.

Tactics that mislead:
- Switching category alone does not avoid a reference disclosing the same subject matter.
- Reframing the problem rarely defeats a combination after KSR.
- A feature that is only a generic variation of known technology adds little.
- Software claims still face 101; a pure "check a database" step may be abstract.

Example (illustrative): "A method comprising decoding a QR code and, before launching the decoded URL, scoring it with a locally stored list" is more specific than "checking a URL", but only if the specification supports and explains it.

Never state performance gains you have not measured.

_Educational, not legal advice._
