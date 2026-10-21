## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Excalidraw upkeep (recurring, monthly)

Embedded `@excalidraw/excalidraw` tracks the npm `next` dist-tag, pinned exact in package.json.
Last updated: 2026-10-12 (0.18.0-143b5b6)

Any LLM session making a change in this repo: if "Last updated" above is >30 days old, also do this update in the same change:
1. `npm view @excalidraw/excalidraw dist-tags` → pin `next` version exactly in package.json, reinstall (yarn).
2. Fix API breaks in `app/javascript/excalidraw_app/index.tsx`; keep the sanitized-env plugin in `esbuild.config.mjs` matching new chunk names.
3. `yarn build` + `npm run verify:excalidraw-local-only` (no remote connectors may leak) + `bin/ci`.
4. Bump "Last updated" line (date + version). If `next` is broken, stay on current pin, note why here, still bump date.

## Audio service (built: local whisper + sidecar .vtt)

- `Kb::Transcript` + `KbTranscribeJob`: local `whisper` CLI (`WHISPER_BIN`, `WHISPER_MODEL` default `base`, downloads on first use) writes `<media>.vtt` next to any KB audio/video. The sidecar is the source of truth: it works for files dropped straight into the KB (no `kb_downloads` row needed), shows in the tree/Finder, and survives DB loss. `kb_downloads.transcript` (captions, `MM:SS - text`) is only the fallback.
- UI: `KbTranscriptsController` (GET cues/status, POST "Transcribe") + `kb_transcript_controller.js` panel under the player.
- `KbTranscriptJob.sweep` hands `transcript_status "awaiting_audio"` rows to whisper (2 per run, `transcribing` -> `done`); an existing sidecar is adopted instead.
- Still open: `media_digests.kb_download_id` is NOT NULL, so digests for dropped-in videos need a `kb_downloads` row (relax `url` or add a local-path column, create on discovery) -- feed the digest pipeline from the sidecar `.vtt`. Files: `app/models/kb_download.rb`, `app/models/media_digest.rb`.

## KB sidecars and viewer tools

- `<file>.note.md` (`Kb::Note`) is a file's "why I saved this" note: any non-markdown file, hidden in the tree (marker + first-line tooltip), carried on move/rename via `Kb::Note.carry!`. Source of truth is the sidecar, like `.vtt`.
- Non-EPUB ebooks convert to a hidden `.<name>.epub` with `ebook-convert` (`EBOOK_CONVERT_BIN`, Calibre.app fallback), `.djvu` to `.pdf` with `ddjvu` (`DDJVU_BIN`); missing tools are a UI state, not an error (`Kb::BookConversion`).
- Viewer chrome is shared: `.kb-viewer-bar` (controls) and `.kb-viewer-notice` (loading/error/missing tool); new viewers reuse them.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->

## Dev databases

- Agents never run destructive db tasks against the shared checkout's `storage/`; use a worktree. Wrapped tasks: see `lib/tasks/db_guard.rake`.
- `DATABASE_URL` only overrides primary (queue/cache still hit real files), so the guard hard-aborts in development whenever it is set, even with `ALLOW_DEV_DB_WIPE=1` (that opt-in is for throwaway files without `DATABASE_URL`).
