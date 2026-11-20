---
title: Configuration
---

Set variables in the environment of the Rails process (for the macOS installer, they are persisted in the generated LaunchAgent plist when passed to `bin/install`). Everything is optional; defaults are shown. A missing external tool disables only its feature.

## Ports and installation

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | 3333 (production), 3000 (`bin/dev`) | Rails port |
| `VOICE_ID_PORT` | 8000 | Host port for the Voice ID service |
| `OCR_SERVICE_PORT` | 8001 | Host port for the OCR service |
| `IDEA_APP_HTTPS_PORT` | 8443 | Local HTTPS proxy port |
| `IDEA_APP_CADDY_HTTP_PORT`, `IDEA_APP_CADDY_ADMIN_PORT` | derived | Per-installation Caddy ports |
| `IDEA_APP_INSTALLATION_NAME` | `idea-app` | Installation name for `bin/start_idea_app.sh` |
| `IDEA_APP_SKIP_CADDY` | derived | `0` or `1`; `1` skips the HTTPS proxy |
| `IDEA_APP_SKIP_COMPOSE` | unset | `1` skips starting sidecar services at startup |
| `IDEA_APP_COMPOSE_BUILD` | unset | `1` rebuilds sidecar images at startup (slow) |
| `IDEA_APP_COMPOSE_CMD` | auto | Override Compose command detection |
| `WEB_CONCURRENCY` | 6 workers | `1` runs Puma in single mode |
| `RAILS_MAX_THREADS` | 4 | Puma threads per worker |
| `BACKLOG_ENABLED` | false | Enable the optional backlog (set at build and run time) |

## Security and storage

| Variable | Default | Purpose |
|----------|---------|---------|
| `IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE` | `storage/recovery_passphrase.key` | Where the app reads and writes the recovery passphrase |
| `IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR` | `../idea-app-sqlcipher-backups` | Where plaintext backups go during encryption |
| `BACKUP_DIR` | unset | Fallback for the plaintext backup location |

Do not put the passphrase in `.env` or Compose secrets; set it from **Settings > Security**.

## Knowledge base tools

Each `*_BIN` variable points to an executable. If unset, the tool is found on `PATH`.

| Variable | Tool / feature | Install |
|----------|----------------|---------|
| `WHISPER_BIN` | `whisper` CLI, audio/video transcripts | `brew install openai-whisper` |
| `WHISPER_MODEL` | Whisper model, default `base` (downloads on first use) | |
| `YT_DLP_BIN` | KB video downloads | `brew install yt-dlp`; a recent build with `curl_cffi` is needed for TED/Vimeo |
| `EBOOK_CONVERT_BIN` | Calibre `ebook-convert` for mobi/azw3/fb2 | `brew install --cask calibre` (the macOS app is found automatically) |
| `DDJVU_BIN` | `ddjvu`, DjVu to PDF | `brew install djvulibre` |
| `SEVEN_ZIP_BIN` | `7z`, rar/7z archive viewer | `brew install p7zip` |
| `TESSERACT_BIN` | Image OCR | `brew install tesseract` |
| `CHROME_BIN` | Headless Chrome/Chromium/Brave for reader PDFs | `brew install --cask google-chrome` |

## OCR service

| Variable | Default | Purpose |
|----------|---------|---------|
| `OCR_SERVICE_URL` | `http://ocr:8000/extract` (launcher sets `http://127.0.0.1:8001/extract`) | OCR endpoint Rails calls |
| `OCR_SERVICE_TIMEOUT` | 900 | Request timeout, seconds |
| `OCR_LONG_DOC_PAGE_THRESHOLD` | 10 | Pages above which documents use the heavy backend |
| `OCR_PAGE_BATCH_SIZE`, `OCR_PDF_DPI` | 4, 192 | Pages per OCR batch, PDF rasterization DPI |
| `OCR_LONG_BACKEND` | `auto` | `auto`, `vllm`, `llamacpp` or `remote` |
| `OCR_LONG_SERVICE_URL` | unset | Already-running endpoint; forces `remote` |
| `OCR_LONG_VLLM_URL`, `OCR_LONG_LLAMACPP_URL` | compose defaults | Backend endpoints |
| `OCR_LONG_IDLE_TIMEOUT` | 300 | Seconds idle before the heavy backend is stopped |
| `OCR_LONG_STARTUP_TIMEOUT` | 900 | Seconds to wait for the backend to start |
| `OCR_LONG_TIMEOUT` | 1800 | Request timeout, seconds |
| `OCR_LONG_PAGES_PER_REQUEST` | 0 | Pages per request; 0 sends the whole document in one request. Lower it (e.g. 8) if GPU memory runs out |
| `OCR_LONG_COMPOSE_CMD`, `OCR_LONG_COMPOSE_FILE` | `docker compose`, `infra/docker-compose.yml` | How the heavy backend is started |
| `OCR_LONG_VLLM_PORT` / `OCR_LONG_LLAMA_PORT` | 8002 / 8003 | Host ports for the heavy backends |
| `OCR_LONG_MODEL_URL`, `OCR_LONG_MMPROJ_URL` | unset | GGUF and projector downloads for the llama.cpp backend |
| `OCR_LONG_LLAMA_NGL`, `OCR_LONG_LLAMA_CTX` | 0, 8192 | GPU layers, context window (llama.cpp container) |

## Voice ID service

| Variable | Default | Purpose |
|----------|---------|---------|
| `VOICE_ID_SERVICE_URL` | `http://voice-id:8000` | Service URL for Rails (host runs: `http://127.0.0.1:8000`) |
| `VOICE_ID_HOST_URL` | `http://localhost:8000` | Fallback URL for host-run Rails |
| `VOICE_ID_WHISPER_MODEL` | image default | faster-whisper model baked in at build time |
| `VOICE_ID_DEVICE` | `cpu` | `cuda` only with GPU-enabled Compose |
| `VOICE_ID_COMPUTE_TYPE` | `int8` | faster-whisper compute type |

## Semantic search service

| Variable | Default | Purpose |
|----------|---------|---------|
| `SEMANTIC_SERVICE_URL` | unset (feature off) | Service URL for Rails (host runs: `http://127.0.0.1:8004`) |

## Credentials (optional email intake)

Resend API key and inbound address, an integrity HMAC key and a webhook token are stored in Rails encrypted credentials (`bin/rails credentials:edit`). See [SETUP.md](https://github.com/Isaac12x/ideafoundry/blob/master/SETUP.md).

See also: [Local services](services.md), [Install](install.md).
