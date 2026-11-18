---
title: Local services
---

Some features use helper services that run in containers next to the app. All are optional. If a service or tool is missing, the app still starts and only that feature shows as unavailable until you fix it. Everything binds to `127.0.0.1`.

| Service | Needed for | Host port |
|---------|-----------|-----------|
| `voice-id` | Voice ID unlock (speech-to-text) | 8000 |
| `ocr` | Text extraction from scans and short PDFs | 8001 |
| `unlimited-ocr-llama` / `unlimited-ocr` | Long documents (books, patents) | 8003 / 8002 |
| local `whisper` CLI | KB audio/video transcripts (not a container) | none |

Definitions live in [`infra/docker-compose.yml`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/docker-compose.yml); overview in [`infra/README.md`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/README.md). Port and tuning variables are on the [Configuration](configuration.md) page.

## Starting and building

Always pass the compose file:

```bash
docker compose -f infra/docker-compose.yml up -d --build      # voice-id + ocr
docker compose -f infra/docker-compose.yml build --no-cache ocr   # first OCR build / Dockerfile changes
docker compose -f infra/docker-compose.yml up -d --no-build voice-id ocr
```

With the macOS installer, `bin/start_idea_app.sh` starts the sidecars in the background on login using existing images only (no rebuilds, Rails is never blocked). It uses the first working runtime among `docker compose`, `docker-compose`, `podman compose`, `podman-compose`. Logs: `log/compose-sidecars.log`. Build the images once yourself first.

## OCR

Surya OCR with a local llama.cpp backend. The first request downloads the model into the `ocr-model-cache` volume and can take several minutes. Rails finds it at `OCR_SERVICE_URL`. Image OCR in the knowledge base also uses the local `tesseract` tool.

## Long-document OCR

Documents longer than `OCR_LONG_DOC_PAGE_THRESHOLD` pages (default 10) go to a heavier Unlimited-OCR backend. It starts on demand when an extraction is queued and stops after `OCR_LONG_IDLE_TIMEOUT` seconds idle. Output is markdown saved beside the source file. You can also force it with **Extract knowledge** in the UI. Extractions run on their own job worker so they never block other jobs.

Choose a backend with `OCR_LONG_BACKEND`:

- `vllm`: NVIDIA GPU, compose service `unlimited-ocr` (`gpu` profile).
- `llamacpp`: Apple Silicon or CPU, compose service `unlimited-ocr-llama` (`gpu` profile). Build with `docker compose -f infra/docker-compose.yml --profile gpu build unlimited-ocr-llama`. You must provide a GGUF model and mmproj, either in the `long-ocr-model-cache` volume or via `OCR_LONG_MODEL_URL` and `OCR_LONG_MMPROJ_URL`.
- `remote`: set `OCR_LONG_SERVICE_URL` to an endpoint you already run; no lifecycle management.
- `auto` (default): a configured `OCR_LONG_SERVICE_URL` forces remote, otherwise an NVIDIA GPU selects vllm.

Docker on a Mac has no GPU access, so the container runs on CPU. For Metal acceleration, run `llama-server` natively and use it as a remote backend:

```bash
brew install llama.cpp
llama-server -m model.gguf --mmproj mmproj.gguf -ngl 999 --host 127.0.0.1 --port 8003 --jinja
export OCR_LONG_SERVICE_URL=http://127.0.0.1:8003/v1
```

The process that runs the long-OCR job worker needs docker CLI access to start and stop the backend. Details: [`infra/services/long_ocr/README.md`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/services/long_ocr/README.md).

## Voice ID

A FastAPI and faster-whisper service. The browser records a short sample, Rails forwards it to the service, and only a derived fingerprint is stored (encrypted with your recovery secret). Audio is not kept. The model is downloaded into the image at build time, so after building it works offline:

```bash
docker compose -f infra/docker-compose.yml build voice-id
docker compose -f infra/docker-compose.yml up -d voice-id
```

Rails running on the host reaches it at `VOICE_ID_SERVICE_URL=http://localhost:8000`. Details: [`infra/services/voice_id/README.md`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/services/voice_id/README.md).

## Transcription (local whisper)

KB audio and video transcribe with the local `whisper` CLI (`brew install openai-whisper`; `WHISPER_BIN`, `WHISPER_MODEL`). The first run downloads the model. The transcript is written as a `.vtt` file next to the media, so it works for files dropped straight into the KB, shows in Finder, and survives database loss. Use **Transcribe** under the player. This is separate from the Voice ID container.

## When something is missing

- No container runtime: OCR and Voice ID are unavailable; everything else works.
- No `whisper`, `ebook-convert`, `ddjvu`, `7z`, `tesseract` or Chrome: the matching viewer or action shows a notice naming the tool and how to install it.
- Check `log/compose-sidecars.log` and `docker compose -f infra/docker-compose.yml ps` for sidecar problems.
