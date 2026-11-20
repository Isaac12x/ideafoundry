# Semantic search over everything, indexed on every change

Internal plan (not published). Builds on `infra/services/semantic` + `SemanticSearch` (commit 1cf5098).

## Goals
- Search reaches EVERY content entity, not just ideas + KB.
- Every change reindexes immediately, only the changed parts are re-embedded.
- Indexing never degrades search: no debounce in Rails, no freeze, search always served.

## Architecture

```
Rails after_commit ──> SemanticRecordIndexJob ──POST /enqueue──> semantic (API)  ──┐ reads (WAL)
KB bust_cache!     ──> SemanticIndexJob (KB delta) ─────────────┘   writes queue    │
                                                                                   ▼
                                     semantic-worker: drain queue, coalesce by id, embed changed chunks only
```

- Two processes, same image, one volume: `semantic` (API: search/enqueue, never embeds documents) and `semantic-worker` (embeds). SQLite WAL: readers never block on the writer, so search keeps answering while indexing runs.
- Queue table keyed by doc id: re-enqueueing an id overwrites its pending payload (latest wins). Bursts collapse in the sidecar; Rails just sends every change.
- Per-chunk hash: docs arrive as `sections` (title+tldr, each paragraph, each note, tags...). Each section is chunked + hashed; only unseen hashes are embedded, the rest reuse stored vectors. Edits touch only their section.
- Blue/green for full rebuilds (model change, corruption): `POST /rebuild` opens a shadow index; the worker writes to live + shadow; a Rails full sweep fills the shadow; `POST /rebuild/commit` swaps atomically. Live index serves throughout.
- No plaintext is stored in the sidecar: only ids, hashes, vectors.

## Sidecar API (contract)
- `GET /health` -> `{status, model, queued, docs, rebuilding}`
- `POST /enqueue {items:[{id, sections:[str]}]}` -> 202 `{queued}`; empty `sections` = delete
- `POST /delete {ids}`, `POST /prune {prefix, keep}` -> queued too
- `POST /search {query|id, prefix, k, exclude, types?}` -> `{hits:[{id, score}]}`; type = 2nd id segment
- `POST /rebuild`, `POST /rebuild/commit`, `POST /rebuild/abort`
- Ids: `u<user_id>:<type>:<key>` (KB key = `<src>:<path>`)

## Rails
1. `SemanticIndexable` concern: `semantic_type`, `semantic_sections` (array of strings), `semantic_owner_id`; `after_commit` enqueue `SemanticRecordIndexJob` (record class + id; missing/blank = delete). No wait, no debounce.
2. `SemanticIndex` registry: every indexed type -> label, scope per user, result title/url/hint. Covers all content models (ideas incl. drafts, notes, todos, lists + items, topologies, themes, problems, facts, maxims, submissions, templates, agent threads/recommendations, KB annotations/bookmarks, licensors + contacts, media digests, knowledge extractions, attachment OCR text, kb_downloads metadata...). Excludes secrets/tokens/system logs.
3. Fan-out: child changes reindex parents (note -> idea; theme/topology rename -> linked ideas).
4. KB: `Kb::TreeBuilder.bust_cache!` enqueues a per-user KB delta job; `KbTranscribeJob` busts after writing `.vtt`. Delta = stat-only walk vs a `semantic_index_entries` manifest (mtime/size); read+send only changed files; delete vanished ones. Recurring 15-min sweep stays as the catch-all for Finder edits.
5. Search: palette Similar mode queries all types, groups results by type label via the registry; TF-IDF fallback stays.
6. Privacy: skip locked projects / private files (existing rules); results re-checked against current access at query time.

## Out of scope
FS watcher (sweep covers out-of-app edits), PDF/ebook text extraction (needs poppler).
