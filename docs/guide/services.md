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

## Set up the sidecar services

A step-by-step walkthrough. Skip any service you do not need.

**1. Prerequisites.** A container runtime (Docker Desktop, OrbStack, Colima or Podman) for the containers, and Homebrew for the native tools. `bin/setup` runs `brew bundle` on [`infra/Brewfile`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/Brewfile), which lists every CLI the app shells out to (`tesseract`, `whisper`, Calibre, and so on). Run it again any time: `brew bundle --file=infra/Brewfile`.

**2. Build and start.** From the repo root:

```bash
docker compose -f infra/docker-compose.yml up -d --build                 # everything that starts by default
docker compose -f infra/docker-compose.yml up -d --build voice-id        # or one at a time
docker compose -f infra/docker-compose.yml up -d --build ocr
docker compose -f infra/docker-compose.yml up -d --build semantic
docker compose -f infra/docker-compose.yml --profile gpu up -d --build unlimited-ocr-llama   # heavy OCR (see Long-document OCR)
docker compose -f infra/docker-compose.yml ps                            # check health
```

The first build downloads models and can take several minutes. The `gpu` profile is never started by default.

**3. Ports and URLs.** Rails running on the host reaches each service on `127.0.0.1`:

| Service | Host port (build/start-time var) | Rails URL variable (runtime) | Value for host-run Rails |
|---------|----------------------------------|------------------------------|--------------------------|
| `voice-id` | 8000 (`VOICE_ID_PORT`) | `VOICE_ID_SERVICE_URL` | `http://127.0.0.1:8000` |
| `ocr` | 8001 (`OCR_SERVICE_PORT`) | `OCR_SERVICE_URL` | `http://127.0.0.1:8001/extract` |
| `unlimited-ocr` (vLLM) | 8002 (`OCR_LONG_VLLM_PORT`) | `OCR_LONG_VLLM_URL` | `http://127.0.0.1:8002/v1` |
| `unlimited-ocr-llama` | 8003 (`OCR_LONG_LLAMA_PORT`) | `OCR_LONG_LLAMACPP_URL` | `http://127.0.0.1:8003/v1` |
| `semantic` | 8004 (`SEMANTIC_SERVICE_PORT`) | `SEMANTIC_SERVICE_URL` | `http://127.0.0.1:8004` |

Two kinds of variables:

- **Build and start time** (read by compose): ports and model choices such as `SEMANTIC_MODEL`, `VOICE_ID_WHISPER_MODEL`, `OCR_LONG_MODEL_URL`. Changing a model needs a rebuild (`up -d --build <service>`). The full list is on the [Configuration](configuration.md) page.
- **Runtime** (read by Rails): the `*_URL` variables above, `WHISPER_BIN`, `EBOOK_CONVERT_BIN`, `DDJVU_BIN`. Changing one needs no rebuild.

**4. Tell Rails where they are.** Pick one:

- **Settings -> Services** (recommended). Edit the URLs and binary paths live, with no restart. A value saved there overrides the environment variable. Clear a field to fall back to the environment, then the built-in default. Each service has a **Test** button (and there is **Test all**) that probes it with the values currently in the form, before you save, and shows the result with its latency. Each row also has a **Set it up** section with the commands above.
- **Environment.** With the macOS installer, `bin/start_idea_app.sh` exports the Voice ID and OCR URLs for you; add your own `export` lines there (or to the `EnvironmentVariables` block of your launchd plist, based on `infra/com.USERNAME.idea-app.plist`) and restart the app. For `bin/dev`, export in your shell first, for example `export SEMANTIC_SERVICE_URL=http://127.0.0.1:8004`.

**5. Verify.** Open Settings -> Services and press **Test all**: a lit lamp means the service answered, a hollow dashed one means it is not configured (off), red shows the error.

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

## Semantic search

Optional local embedding and vector service behind the command palette's **Similar** mode, so it matches by meaning instead of shared keywords. Rails indexes your ideas and knowledge-base files (name, note and text) into it: on every idea save, plus a full sweep every 15 minutes. Start it and point Rails at it (host port 8004):

```bash
docker compose -f infra/docker-compose.yml up -d semantic
export SEMANTIC_SERVICE_URL=http://127.0.0.1:8004
```

With `SEMANTIC_SERVICE_URL` unset, or the service down or not yet indexed, Similar falls back to the built-in keyword (TF-IDF) ranking. Nothing breaks. Details: [`infra/services/semantic/README.md`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/services/semantic/README.md).

## Transcription (local whisper)

KB audio and video transcribe with the local `whisper` CLI (`brew install openai-whisper`; `WHISPER_BIN`, `WHISPER_MODEL`). The first run downloads the model. The transcript is written as a `.vtt` file next to the media, so it works for files dropped straight into the KB, shows in Finder, and survives database loss. Use **Transcribe** under the player. This is separate from the Voice ID container.

## When something is missing

- No container runtime: OCR, Voice ID and semantic search are unavailable (Similar uses keywords); everything else works.
- No `whisper`, `ebook-convert`, `ddjvu`, `7z`, `tesseract` or Chrome: the matching viewer or action shows a notice naming the tool and how to install it.
- Check `log/compose-sidecars.log` and `docker compose -f infra/docker-compose.yml ps` for sidecar problems.
