# infra/

Everything that runs outside the Rails process. Rails-side clients (`app/services/long_ocr/`, voice/OCR clients, `Kb::Transcript` with the local `whisper` CLI) stay in `app/`.

| Path | What |
|------|------|
| `Brewfile` | macOS system deps, source of truth (`bin/install`/`bin/setup` run `brew bundle --file=infra/Brewfile`) |
| `Dockerfile` | Rails app image; build from repo root: `docker build -f infra/Dockerfile .` Final-stage apt list mirrors the Brewfile (manual sync) |
| `docker-compose.yml` | Sidecars; project name pinned `idea-app` |
| `Caddyfile`, `Caddyfile.instance` | Local `ideas.local` reverse proxy to Rails (`.instance` = per-installation template with placeholders) |
| `com.USERNAME.idea-app.plist` | launchd template installed by `bin/install` |
| `services/ocr/` | Surya OCR sidecar (FastAPI + llama.cpp) |
| `services/long_ocr/` | llama.cpp Unlimited-OCR heavy backend (`gpu` profile) |
| `services/voice_id/` | faster-whisper Voice ID sidecar |
| `services/semantic/` | fastembed + sqlite vector index (semantic search/related) |

## Compose

Always pass the file: `docker compose -f infra/docker-compose.yml <cmd>`. Default graph = sidecars only (`voice-id`, `ocr`); Rails runs under launchd/systemd. Profiles: `app` (Rails `web`), `gpu` (heavy OCR, started on demand).

## Services

| Service | Port (host) | Key env | Rails reaches it via |
|---------|-------------|---------|----------------------|
| `voice-id` (`services/voice_id`) | 127.0.0.1:8000 (`VOICE_ID_PORT`) | `VOICE_ID_WHISPER_MODEL`, `VOICE_ID_DEVICE`, `VOICE_ID_COMPUTE_TYPE` | `VOICE_ID_SERVICE_URL` (`LocalVoiceIdClient`) |
| `semantic` (`services/semantic`) | 127.0.0.1:8004 (`SEMANTIC_SERVICE_PORT`) | `SEMANTIC_MODEL` (build arg + env), `SEMANTIC_DB` | `SEMANTIC_SERVICE_URL` |
| `ocr` (`services/ocr`) | 127.0.0.1:8001 (`OCR_SERVICE_PORT`) | `SURYA_INFERENCE_*`, `OCR_PAGE_BATCH_SIZE`, `OCR_PDF_DPI`, `OCR_LONG_DOC_PAGE_THRESHOLD` | `OCR_SERVICE_URL` (`.../extract`) |
| `unlimited-ocr` (vLLM image, NVIDIA) | 127.0.0.1:8002 (`OCR_LONG_VLLM_PORT`) | `OCR_LONG_MODEL` | `OCR_LONG_VLLM_URL` |
| `unlimited-ocr-llama` (`services/long_ocr`) | 127.0.0.1:8003 (`OCR_LONG_LLAMA_PORT`) | `OCR_LONG_MODEL_URL`, `OCR_LONG_MMPROJ_URL`, `OCR_LONG_LLAMA_NGL`, `OCR_LONG_LLAMA_CTX` | `OCR_LONG_LLAMACPP_URL`; lifecycle by `LongOcr::ServiceSupervisor` |

Heavy backend selection: `OCR_LONG_BACKEND=auto|vllm|llamacpp|remote` (`OCR_LONG_SERVICE_URL` for remote). Details: `SETUP.md`, each service's README.

```bash
docker compose -f infra/docker-compose.yml up -d --build          # sidecars
docker compose -f infra/docker-compose.yml --profile app up       # + Rails container
docker compose -f infra/docker-compose.yml --profile gpu build unlimited-ocr-llama
```

## Adding a service

- New out-of-process service (AI, voice, OCR, ...): `infra/services/<name>/` with `Dockerfile` + `README.md`; register in `infra/docker-compose.yml`; Rails gets its URL from an ENV var (client code stays in `app/`).
- New shell-out CLI: add to `infra/Brewfile`, the `infra/Dockerfile` final-stage apt list, and `PACKAGES` in `test/brewfile_test.rb` (CI fails otherwise).

## Process model

Launchd runs `bin/start_idea_app.sh` -> Puma cluster (6 workers, `preload_app!`, `WEB_CONCURRENCY=1` for single mode) + `bin/jobs` (Solid Queue) as separate processes. Workers share the unlock state through the OS keychain plus `tmp/recovery_generation`; see DEVELOPMENT.md "Process model".
