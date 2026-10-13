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

## Audio service (not built yet)

- When building it, also make videos dropped straight into the KB trackable: they have no `kb_downloads` row (`url` NOT NULL + http(s) validation; `media_digests.kb_download_id` NOT NULL).
- Relax `url` or add a local-path column, create rows on discovery, run them through the same `transcript_status` flow.
- Pick up rows with `transcript_status "awaiting_audio"` (no captions / direct video files).
- Files: `app/models/kb_download.rb`, `app/models/media_digest.rb` (see comment), `app/jobs/kb_transcript_job.rb`, `app/services/kb/video_transcript.rb`.

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
