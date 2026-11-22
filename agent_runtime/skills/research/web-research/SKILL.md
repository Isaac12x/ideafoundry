---
name: web-research
description: "Use for ANY task needing information from the web — answering factual questions, investigating a topic, comparing options, gathering current/recent developments, verifying a claim, or producing a sourced report. The methodology for searching, reading, cross-verifying, and citing so answers are accurate and traceable, not guessed."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Research, Web, Search, Verification, Sources, Citations, OSINT, Fact-Checking]
    related_skills: [arxiv, blogwatcher, polymarket, llm-wiki, research-paper-writing]
---

# Web Research

Turn a question into a **verified, cited** answer instead of a plausible guess. This is the default playbook whenever a task depends on facts you don't already know, on anything that changes over time, or on anything a user could check and find wrong.

## Use this when

- The answer depends on external facts (who/what/when/how much/current status).
- The topic post-dates or falls outside your training, or is niche/local/fast-moving.
- A claim needs verifying, or two sources might disagree.
- You're asked to compare, survey, or write a report from sources.

**Don't** over-research the trivial. One good search beats a five-source ceremony for "what port does Postgres use." Match effort to stakes and volatility. `ponytail: effort scales with how wrong the answer could be.`

## Your tools

| Tool | Use for | Notes |
|------|---------|-------|
| `web_search(query, limit)` | Finding sources, discovering what exists | Supports `site:` `filetype:` `intitle:` `-term` `"exact phrase"`. Default 5 results; raise `limit` for surveys. |
| `web_extract(urls[])` | Reading the actual page/PDF content | Up to 5 URLs/call. Handles PDFs (arxiv, reports). Big pages get LLM-summarized — extract fewer URLs when you need verbatim detail. |
| `browser_*` | Pages that fail extract: JS-rendered, login/paywall walls, interactive, infinite-scroll | The escalation path. Slower — use only when `web_extract` returns junk or errors. |
| `x_search` | Real-time chatter, breaking events, sentiment, dev/announcement threads | Primary-ish for "what are people saying right now." Treat individual posts as claims, not facts. |

**Search finds; extract confirms.** A search snippet is a lead, never a citation. Never quote, cite, or state a specific fact (number, date, name, quote) from a snippet alone — open the page and read it. See [references/search-operators.md](references/search-operators.md) for query craft.

## The loop

Run this loop; iterate until the question is actually answered, not just until you have some text.

### 1. Frame
State, in one line, what a complete answer contains and how you'd know it's right. Decompose multi-part questions into sub-questions — research each, don't blur them. Note the time-sensitivity: "as of when" matters for anything that changes.

### 2. Search
Start broad to map the terrain, then go specific with operators. Prefer the vocabulary the *source* would use, not the user's phrasing (a spec says "throughput," a forum says "how fast"). If results are junk after 2 tries, the query is wrong — change the terms, don't page deeper. Reformulate 3+ ways for anything important.

### 3. Read
`web_extract` the most promising 2–4 results — go to primary/authoritative sources, not the SEO blog that repackaged them. Read enough to actually know, not just enough to pattern-match a sentence. If extract fails or returns boilerplate, escalate to `browser_*`.

### 4. Cross-verify
**One source is a lead; two independent sources is a fact.** For any load-bearing claim, confirm it in a second *independent* source (not three sites quoting the same press release — that's one source wearing hats). Prefer the primary source over anyone summarizing it. See [references/source-evaluation.md](references/source-evaluation.md).

### 5. Resolve conflicts
When sources disagree, don't silently pick one. Check dates (is one stale?), authority (who'd actually know?), and primacy (who's closest to the fact?). If it stays genuinely contested, **report the disagreement** — "X says A, Y says B, unresolved" is a correct answer; a confident wrong pick is not.

### 6. Synthesize & cite
Answer the *original* question directly first, then support. Every non-obvious factual claim carries its source URL. Distinguish what you verified from what you're inferring. State the "as of" date for anything time-sensitive. Name what you couldn't confirm rather than papering the gap.

## Citation discipline — non-negotiable

- **Never fabricate** a URL, title, quote, statistic, or date. If you didn't read it, you don't cite it. A made-up citation is worse than "I couldn't find this."
- Every specific claim → a source the reader can open and check.
- Quote verbatim from extracted content only; paraphrase everything else and mark it as paraphrase.
- Carry the "as of" date on volatile facts (prices, versions, leadership, standings, "latest").
- Separate **found** (verified) from **inferred** (your reasoning) from **not found** (gap). Never let them blur.

## Escalation ladder

`web_search` → `web_extract` → `browser_*`. Climb only when the rung below fails:
- Extract returns nav-junk / empty / paywall → `browser_*` to render it.
- Search surfaces nothing → reformulate with source-native terms and operators before assuming it doesn't exist. Absence of evidence ≠ evidence of absence; say "couldn't find," not "doesn't exist."
- Real-time / social → `x_search`. Domain-specific sources (papers → [[arxiv]], feeds → [[blogwatcher]], markets → [[polymarket]]) → use the dedicated skill.

## Deep research (big / multi-part questions)

For a broad question with independent sub-areas, **fan out**: dispatch parallel sub-agents (see [[dispatching-parallel-agents]]), one per sub-question, each running this loop and returning cited findings. Then synthesize into one structured report: direct answer up top → evidence with citations → conflicts/uncertainties → what couldn't be confirmed. Parallelize only truly independent branches; sequence anything where one finding drives the next query.

## Red flags — stop and fix

| Thought | Reality |
|---------|---------|
| "The snippet says X, good enough." | Snippets mislead. Open the page. |
| "One source confirms it." | One source is a lead. Get a second, independent one. |
| "These 3 sites agree." | Check they're not all quoting one origin. |
| "I'm fairly sure the URL is roughly…" | Don't cite it. Fabricated citations are the cardinal sin. |
| "Sources disagree, I'll pick the confident one." | Report the disagreement. |
| "It's probably still current." | Anything volatile needs an "as of" check. |
| "No results, so it doesn't exist." | Reformulate first. Then say "couldn't find," not "doesn't exist." |
| "This is taking long, I'll fill the gap from memory." | Mark it unconfirmed. Never launder a guess as a finding. |
