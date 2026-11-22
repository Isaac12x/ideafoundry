---
title: "Claim tree"
slug: claim-tree
cluster: claims
jurisdiction: US
aliases: ["claim hierarchy", "claim chart of dependencies"]
related: ["independent-claim", "dependent-claim", "three-tier-claim-set"]
sources: ["Patents - provisional claims and provisional claims to non-provisional patent tree .pdf"]
corrections: []
links: ["https://www.uspto.gov/web/offices/pac/mpep/s608.html#d0e45256"]
---
A claim tree is a diagram of how claims depend on one another: independent claims at the roots, dependents branching below. Drafters use it to check coverage and count fees.

What to check:
- Each independent claim covers one category (method, system, medium) and a distinct scope.
- Each dependent's numbers point to the correct parent (renumbering after deleting claims commonly leaves wrong references).
- Fee thresholds: the base filing allows three independent and twenty total claims.
- Every branch has support in the specification (written description).

Example:
```
1 (method)
 ├─ 2 local database
 │   └─ 3 daily update
 └─ 4 blocking action
10 (system) mirrors 1
15 (medium) mirrors 1
```

Tip: in a provisional-to-non-provisional workflow, draw the tree once for the planned claim set, then map each node to specification paragraphs (claim-to-spec mapping) so no limitation is unsupported.

_Educational, not legal advice._
