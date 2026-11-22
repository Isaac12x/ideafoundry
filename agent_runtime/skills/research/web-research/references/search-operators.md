# Search Operators & Query Craft

Sharper queries for `web_search`. Operators are passed through to the backend, so they work when the backend supports them — if one seems ignored, fall back to plain terms.

## Operators

| Operator | Effect | Example |
|----------|--------|---------|
| `site:domain` | Restrict to one site | `site:docs.python.org asyncio gather` |
| `-term` | Exclude | `jaguar speed -car -animal` |
| `"exact phrase"` | Require the phrase verbatim | `"rate limit" "429" cloudflare` |
| `filetype:pdf` | Restrict file type | `transformer architecture filetype:pdf` |
| `intitle:word` | Word must be in the title | `intitle:changelog react 19` |
| `OR` | Either term | `postgres OR mysql json indexing` |

Combine them: `site:github.com "memory leak" filetype:md -archived`.

## Query strategy

- **Broad → narrow.** First query maps the landscape and teaches you the vocabulary; later queries use that vocabulary to pinpoint.
- **Speak the source's language.** Search the terms a primary source would use, not the user's casual phrasing. A spec says "idempotency"; a user says "won't double-charge." Try both.
- **Decompose.** Break a compound question into one query per sub-fact. "Best X for Y in 2026" → separate searches for candidates, for benchmarks, for recent changes.
- **Reformulate, don't paginate.** If the first page is junk, the *query* is wrong — change the words. Paging to result 30 of a bad query rarely helps.
- **Triangulate with different angles.** For anything important, run 3+ phrasings; sources that only surface under one phrasing are worth noticing.
- **Raise `limit`** for surveys/landscape scans (want breadth); keep it low for a known-item lookup (want the one right page).

## Targeting source types

- **Official docs / primary:** `site:` the vendor or standards body.
- **Recent developments:** add the year, "latest", "2026", "changelog", "release notes". Cross-check the publish date on the page — search freshness lies.
- **Primary documents:** `filetype:pdf` for papers, filings, whitepapers, spec sheets.
- **Discussion / real experience:** `site:news.ycombinator.com`, `site:reddit.com`, `site:stackoverflow.com`, or `x_search` for live chatter.
- **Code / issues:** `site:github.com` with `intitle:` or `"error string"`.
- **Exact error messages:** paste the literal string in `"quotes"`, strip the parts unique to your machine (paths, IDs).

## When search returns nothing useful

1. Drop to fewer, more essential keywords — over-specific queries starve.
2. Swap in synonyms / the source-native term.
3. Remove operators one at a time (a wrong `site:` or over-tight `"phrase"` can zero out results).
4. Try an adjacent question that would surface the same source.
5. Only after genuine reformulation: conclude **"couldn't find,"** not "doesn't exist."
