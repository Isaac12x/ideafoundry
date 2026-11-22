---
title: "Enablement"
slug: enablement
cluster: specification
jurisdiction: US
aliases: ["enablement requirement", "Wands factors", "Amgen v. Sanofi", "undue experimentation"]
related: ["written-description-112a", "posita", "best-mode"]
sources: ["Patents.pdf", "Patents - detailed description.pdf"]
corrections: ["Source cites Ariad for enablement; Ariad is written description. Enablement authorities are Wands and Amgen v. Sanofi (2023)"]
links: ["https://www.uspto.gov/web/offices/pac/mpep/s2164.html"]
---
Enablement (35 USC 112(a)) requires the specification to teach a skilled person how to make and use the **full scope** of the claimed invention without undue experimentation.

Authorities:
- **In re Wands** (1988): factors including breadth of claims, nature of invention, state of the art, level of skill, predictability, direction in the specification, working examples, and quantity of experimentation.
- **Amgen v. Sanofi** (Supreme Court, 2023): a claim to a whole genus of functionally defined antibodies was not enabled; the specification must enable the full breadth of the claim, not just a few embodiments.

Software: describe the algorithm, data structures, inputs, and outputs in enough detail to implement it; functional claims with no teaching of how fail.

Example: a claim "any method of detecting phishing" with only one rule-based detector described is at risk. Claiming detection by comparing a decoded hostname to a list, with the comparison method described, is enabled.

Tip: use realistic worked examples; label hypothetical results as prophetic and do not present unperformed results as done.

_Educational, not legal advice._
