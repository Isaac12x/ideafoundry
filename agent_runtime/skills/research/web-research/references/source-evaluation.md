# Source Evaluation

How to judge whether a source can carry a claim. Applied during step 4 (cross-verify) and 5 (resolve conflicts) of the [web-research](../SKILL.md) loop.

## Primary vs. secondary vs. tertiary

- **Primary** — the origin of the fact: the paper itself, the SEC filing, the API docs, the official announcement, the raw dataset, the person's own post, the court record. Prefer these. Closest to truth, least distortion.
- **Secondary** — someone reporting on a primary source: news articles, analyst notes, review sites. Useful for context and for *finding* the primary. Verify their claims against the primary before relying on a specific number or quote.
- **Tertiary** — summaries of summaries: most SEO blogs, content farms, AI-generated listicles, aggregators. Use as leads only. Never a citation for a specific fact.

**Rule:** the more specific the claim (a number, a date, an exact quote), the closer to primary your source must be.

## Independence

Two sources only corroborate if they're **independent**. Three outlets running the same wire story, or ten blogs citing one tweet, are *one* source. Trace claims upstream: if they all funnel to the same origin, you have one data point. Real corroboration comes from sources that reached the fact by different routes.

## Authority — would this source actually know?

- Does the author/org have direct access to the fact, or are they speculating from a distance?
- Domain expertise vs. generalist rewrite.
- Official/primary channel vs. third-party interpretation.
- For data: is methodology stated? Sample size? Can it be reproduced or checked?

## Recency

- When was it published *and* last updated? A great 2019 answer can be wrong now.
- For volatile facts (prices, versions, leadership, rankings, "current best"), require recent sourcing and carry an "as of {date}".
- For stable facts (historical events, math, established science), age is fine.
- Beware undated pages — treat unknown-date content as low-confidence for anything time-sensitive.

## Bias & incentive

- Who benefits from you believing this? Vendor benchmarking its own product; a site selling the thing it "reviews"; advocacy framing.
- Not disqualifying — a vendor's own docs are the primary source for its API. Just weight the incentive and cross-check contested claims against a disinterested source.

## Quick confidence tiers

- **High** — primary source, or two independent authoritative sources agree, recent enough for the claim. State it plainly.
- **Medium** — one credible secondary source, or minor unresolved detail. State it, flag the basis.
- **Low** — single tertiary source, undated, or incentive-conflicted with no corroboration. Present as "one source claims…," or keep digging.
- **Unverified** — couldn't confirm. Say so explicitly. Do not upgrade a guess to a finding to fill the gap.

## When sources conflict

1. **Dates** — is one simply outdated? Newer often wins, but confirm it's not just newer *noise*.
2. **Primacy** — who's closest to the fact? Primary beats a summary of it.
3. **Authority** — who would actually know?
4. **Independence** — is the "majority" really just one origin repeated?
5. Still genuinely contested → **report the disagreement with both sources.** An honest "unresolved: X says A, Y says B" beats a confident wrong pick.
