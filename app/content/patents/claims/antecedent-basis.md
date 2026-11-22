---
title: "Antecedent basis"
slug: antecedent-basis
cluster: claims
jurisdiction: US
aliases: ["antecedent", "a vs the"]
related: ["definiteness-112b", "claim-wording-dos-donts"]
sources: ["Patents - provisional claims and provisional claims to non-provisional patent tree .pdf", "Patents - technical disclosure and legal scaffold .pdf", "Patents - pre-filling quality control.pdf"]
corrections: []
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2173.html#d0e218320"]
---
Antecedent basis means every "the X" or "said X" in a claim must point back to an "a X" introduced earlier in that claim (or a parent claim). It is a definiteness issue under 35 USC 112(b).

Rules of thumb:
- First mention: "a processor". Later: "the processor".
- Do not introduce an element twice with "a".
- Check pronouns and derived terms: "the determined value" needs a prior "determining a value".
- In a dependent claim, "the" terms must trace to the parent claim chain.

Bad: "...comparing the hostname to the list" when no hostname or list was introduced.
Better: "...extracting a hostname from the URL; and comparing the hostname to a list."

A missing antecedent is not always fatal if the scope is still reasonably clear from context (MPEP 2173.05(e)), but examiners reject it routinely, and it invites ambiguity litigation.

Tip: before filing, read every claim and mark each "the" with its "a". Revising claims after removing elements often breaks chains; re-check after every edit.

_Educational, not legal advice._
