# Patent Reference — plan

Terms: see GLOSSARY.md "Patent learning".

## Phase 1 — content (now)
Notes: `app/content/patents/<cluster>/<slug>.md`. Front matter:

```yaml
title: Dependent claim
slug: dependent-claim          # unique across all clusters, used by chips/tools
cluster: claims
jurisdiction: US               # US | EP | PCT | general
aliases: [dependent claims]    # palette/lookup synonyms
related: [independent-claim]   # slugs
sources: ["Patents.pdf"]       # or ["not from sources"]
corrections: ["Ariad is written description, not enablement"]  # "corrected from source" items
links: ["https://www.uspto.gov/..."]  # official pages for fees/forms/codes
```
Body: <=300 words, plain explanation, one short example, ends with
`_Educational, not legal advice._`. No dollar amounts, form/document codes → link (Q11/Q12).

Clusters: claims, specification, drawings, provisional, prior-art, prosecution, portfolio, workflows (+ example).
Drafted by Sonnet agents per cluster from `scratchpad/t/*.txt`; owner reviews before ship.

## Phase 2 — app
1. `PatentReference` (PORO): loads notes (front matter + body) once, `find(slug)`, `search(q)`, `by_cluster`.
2. Route `/reference` (index by cluster) + `/reference/:slug`; render via `Kb::MarkdownRenderer`.
3. Palette: "Reference" group (title/alias match; SemanticIndex registration if sidecar up).
4. Help chip partial `reference/_chip` (`<details data-controller="popover">`); place on idea show; agent citations `[[note:slug]]` render as chips.
5. Agent: toolbox `search_reference`, `lookup_patent_note`; model agent: top-k notes appended to system prompt when thread is patent-related.
6. Tests: loader (front-matter valid, slugs unique, related resolve), controller, tools. `bin/ci`.

## Later
Chips on prior-art evidence links, drafting screens.
