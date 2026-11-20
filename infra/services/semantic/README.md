# semantic

Local embedding + vector index sidecar (FastAPI + fastembed/ONNX on CPU, no torch). Two compose services, one image and one volume (`semantic-data`):

- `semantic`: API (`uvicorn app:app`, port 8000). Search + enqueue; embeds only the short search query, never documents.
- `semantic-worker`: `python app.py worker`. Drains the queue (64 ids/batch, polls every 0.5s when idle), embeds, writes the index.

Rails client reads `SEMANTIC_SERVICE_URL`. Model (`BAAI/bge-small-en-v1.5`, build arg/env `SEMANTIC_MODEL`) is baked into the image.

## Storage (all sqlite, WAL, busy_timeout 10s; base path = `SEMANTIC_DB`)

- `<db>.control`: `queue(id PK, op, payload, enqueued_at)` + `meta` (active/shadow index pointers). Queue payload is section text, held only until processed (secure_delete on), never in the index.
- `<db>.idx<N>`: `docs(id, hash)`, `chunks(doc_id, n, hash, vec)`, `meta(model)`. Only ids, hashes, float32 vectors.
- Old pre-queue `semantic.sqlite3` is ignored; delete it. Do a full sweep (or `/rebuild`) after upgrading.

Doc = `sections` (strings). Each section is chunked (~1000 chars, 200 overlap, max 64/section), each chunk sha256-hashed. Worker embeds only hashes not already stored (in live, plus shadow when rebuilding, if the index model == current model), then rewrites that doc's rows in one short transaction. Queue row is removed only if `enqueued_at` is unchanged, so a newer enqueue is never lost. Crash-safe: the queue persists, reprocessing is idempotent.

## Endpoints (JSON)

- `GET /health` -> `{"status":"ok","model","queued","docs","rebuilding"}` (docs = live index)
- `POST /enqueue {"items":[{"id","sections":[str]}]}` -> 202 `{"queued"}`. Same id again = overwrite (latest wins). Empty/blank `sections` = delete.
- `POST /delete {"ids"}` -> 202 `{"queued"}`
- `POST /prune {"prefix","keep"}` -> 202 `{"queued"}`. Ids to delete (indexed docs under prefix not in keep) are resolved at enqueue time into delete ops.
- `POST /search {"query"|"id","prefix","k":12,"exclude":[],"types":null}` -> `{"hits":[{"id","score"}]}`. One of query/id (400), prefix required (422). `types` filters on the 2nd `:` segment of the id (`u1:idea:5` -> `idea`). Doc score = max chunk cosine; id mode = mean of that doc's chunks.
- `POST /rebuild` -> `{"rebuilding":true,"started":bool}`: opens an empty shadow index; the worker applies every op to live and shadow. Live keeps serving.
- `POST /rebuild/commit` -> `{"rebuilding":false,"committed":true}`: atomic pointer flip to shadow, old file deleted. 409 if not rebuilding. Caller must have re-sent everything first (and let `queued` reach 0).
- `POST /rebuild/abort` -> `{"rebuilding":false,"aborted":true}`.
- `/upsert` is removed.

If `SEMANTIC_MODEL` changes: `/rebuild`, then resend everything; shadow embeds fresh (no reuse from the old-model live index).

## Test / build

```bash
cd infra/services/semantic && python3 -m pytest -q   # fake embedder, needs fastapi httpx numpy pytest
docker compose -f infra/docker-compose.yml up -d --build semantic semantic-worker
```
