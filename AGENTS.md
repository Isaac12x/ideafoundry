## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, invoke the `skill` tool with `skill: "graphify"` before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Excalidraw upkeep

Recurring monthly task — see "Excalidraw upkeep" in CLAUDE.md. If its "Last updated" date is >30 days old, do it as part of your change.

## Audio service (not built yet)

- When building it, also make videos dropped straight into the KB trackable: they have no `kb_downloads` row (`url` NOT NULL + http(s) validation; `media_digests.kb_download_id` NOT NULL).
- Relax `url` or add a local-path column, create rows on discovery, run them through the same `transcript_status` flow.
- Pick up rows with `transcript_status "awaiting_audio"` (no captions / direct video files).
- Files: `app/models/kb_download.rb`, `app/models/media_digest.rb` (see comment), `app/jobs/kb_transcript_job.rb`, `app/services/kb/video_transcript.rb`.
