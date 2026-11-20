# Glossary

Shared vocabulary for agents and contributors. User-facing setup lives in [docs/guide/](docs/guide/).

## Product and data

| Term | Meaning |
|------|---------|
| **Idea** | Central record in the workbench: lifecycle state, scoring, notes, media, and links to KB and planning artifacts. |
| **Knowledge base (KB)** | Local folder tree the app indexes and serves; files may have hidden sidecars (notes, transcripts, sources). |
| **Palette** | Command palette (Quick / Deep / Similar search modes). **Similar** uses semantic vectors when the sidecar is up, else TF-IDF. |
| **Provenance** | Activity and checksum history for how content changed (ideas, edits, imports, agent work). |
| **Project** | Scoped workspace in the KB; can be locked; media cache rules differ from the open KB. |
| **Sidecar (file)** | Companion file next to KB media, e.g. `<file>.vtt`, `<file>.note.md`, `<file>.source.json` — filesystem is source of truth. |
| **Topology** | Category / relationship graph over ideas (3D view and filters). |

## Semantic search

| Term | Meaning |
|------|---------|
| **Semantic index id** | Stable string `u<user_id>:<type>:<key>` sent to the sidecar (KB keys use `src:path`). |
| **SemanticIndexable** | Rails concern: models declare `semantic_type`, `semantic_sections`, and enqueue on `after_commit`. |
| **SemanticIndex** | Registry mapping each indexed type to labels, scopes, and result URLs for palette grouping. |
| **SemanticRecordIndexJob** | Per-record enqueue after DB commits; blank sections mean delete. |
| **SemanticIndexJob** | KB delta job: compares mtime/size manifest, enqueues changed/vanished files only. |
| **Section** | One embeddable text slice (title, paragraph, tag line, etc.); hashed per chunk so only edits re-embed. |
| **Coalescing queue** | Sidecar queue keyed by doc id; latest payload wins under burst writes. |
| **Blue/green rebuild** | Sidecar builds a shadow index, worker dual-writes, `rebuild/commit` swaps atomically. |
| **TF-IDF fallback** | In-app lexical Similar search when the semantic sidecar is absent or unreachable. |

## Infrastructure

| Term | Meaning |
|------|---------|
| **Sidecar (service)** | Optional local container next to Rails (`voice-id`, `ocr`, `unlimited-ocr*`, `semantic`). See `infra/docker-compose.yml`. |
| **semantic / semantic-worker** | API process (search + enqueue, no embedding) and worker process (embed + drain queue), one SQLite WAL volume. |
| **ServiceRegistry** | Built-in defaults for service URLs and tool paths. |
| **ServiceSetting** | Per-install overrides from **Settings → Services**; overrides ENV, then registry. |
| **Brewfile** | `infra/Brewfile` — canonical list of host CLIs the app shells out to (whisper, yt-dlp, Calibre, etc.). |
| **Solid Queue** | Rails background job backend (`bin/jobs` in production). |

## Security and locks

| Term | Meaning |
|------|---------|
| **Typing lock** | Unlock by typing rhythm; cover pauses media and may clear HTTP cache after lock. |
| **Voice ID** | Local speech-to-text sidecar for voice-based unlock (not KB transcription). |
| **SQLCipher** | Encrypted SQLite used in production. |