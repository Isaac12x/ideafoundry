# semantic

Local embedding + vector index sidecar (FastAPI + fastembed/ONNX on CPU, no torch; port 8000 in the container). `semantic` service in `infra/docker-compose.yml`. Rails client reads `SEMANTIC_SERVICE_URL`.

Model (`BAAI/bge-small-en-v1.5`, build arg/env `SEMANTIC_MODEL`) is baked into the image at build time, so it works offline. Storage is one sqlite file (`SEMANTIC_DB`, default `/data/semantic.sqlite3`, compose volume `semantic-data`): `docs(id, hash)`, `chunks(doc_id, n, vec)` with float32 blobs. Text is chunked (~1000 chars, 200 overlap, max 64 chunks/doc). Search is numpy brute-force cosine, loaded per query: fine to ~100k chunks, then move to sqlite-vec/HNSW.

## Endpoints (JSON)

- `GET /health` -> `{"status":"ok","model":"..."}`
- `POST /upsert {"items":[{"id","text"}]}` -> `{"embedded","skipped"}`. Same sha256 of text = skipped; empty text deletes the id.
- `POST /delete {"ids":[...]}` -> `{"deleted"}`
- `POST /prune {"prefix","keep":[...]}` -> `{"deleted"}`. Deletes docs starting with `prefix` not in `keep`.
- `POST /search {"query"|"id","prefix","k":12,"exclude":[]}` -> `{"hits":[{"id","score"}]}`. Exactly one of `query`/`id` (400 otherwise). `prefix` required, non-empty (422). `id` mode uses the mean of that doc's chunks, excludes itself, `[]` if unknown. Doc score = max chunk cosine.

```bash
curl -s localhost:8004/upsert -H 'content-type: application/json' \
  -d '{"items":[{"id":"u1:idea:1","text":"solar powered boat"}]}'
curl -s localhost:8004/search -H 'content-type: application/json' \
  -d '{"query":"electric ship","prefix":"u1:"}'
curl -s localhost:8004/search -H 'content-type: application/json' \
  -d '{"id":"u1:idea:1","prefix":"u1:","k":5}'
```

## Test / build

```bash
cd infra/services/semantic && python3 -m pytest -q   # fake embedder, needs fastapi httpx numpy pytest
docker compose -f infra/docker-compose.yml build semantic
```
