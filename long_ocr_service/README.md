# Unlimited-OCR — llama.cpp port (on-demand heavy OCR)

Apple Silicon / CPU port of the heavy long-document OCR backend used by the
knowledge-extraction pipeline. Runs `llama-server` (from official llama.cpp
release binaries) serving a DeepSeek-OCR / Unlimited-OCR GGUF over an
OpenAI-compatible `/v1` API, the same surface as the NVIDIA vLLM recipe
(`recipes.vllm.ai/baidu/Unlimited-OCR`). `LongOcr::Client` talks to all three
backends (vllm / llamacpp / remote) identically.

## How it's used

This service is **not** in the default compose graph. It lives under the `gpu`
profile and is started on demand by `LongOcr::ServiceSupervisor` when a long
document is enqueued, then stopped by `LongOcrIdleStopJob` once idle:

```
docker compose --profile gpu up -d unlimited-ocr-llama   # supervisor does this
docker compose stop unlimited-ocr-llama                  # idle-stop job does this
```

## Model files

Provide a GGUF + multimodal projector (`mmproj`). Either bake them into the
`long-ocr-model-cache` volume at `/models/model.gguf` + `/models/mmproj.gguf`,
or set download URLs:

```
OCR_LONG_MODEL_URL=https://huggingface.co/<repo>/resolve/main/deepseek-ocr.gguf
OCR_LONG_MMPROJ_URL=https://huggingface.co/<repo>/resolve/main/mmproj.gguf
```

> Vision support for DeepSeek-OCR in llama.cpp depends on a working GGUF +
> mmproj conversion. Pin `LLAMA_CPP_REF` to a release that supports the model's
> architecture. If no working GGUF is available yet, use the vLLM backend
> (`OCR_LONG_BACKEND=vllm`) or a remote endpoint (`OCR_LONG_SERVICE_URL`).

## Tunables (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `OCR_LONG_MODEL_PATH` | `/models/model.gguf` | GGUF location |
| `OCR_LONG_MMPROJ_PATH` | `/models/mmproj.gguf` | mmproj location |
| `OCR_LONG_MODEL_URL` / `OCR_LONG_MMPROJ_URL` | — | download if missing |
| `LLAMA_NGL` | `0` | layers offloaded to GPU |
| `LLAMA_CTX_SIZE` | `8192` | context window |

## macOS Metal

Docker Desktop has no GPU passthrough, so the container runs CPU-only on a Mac.
For Metal acceleration, run `llama-server` natively on the host and point the app
at it as a remote backend:

```
brew install llama.cpp   # or build with LLAMA_METAL=1
llama-server -m model.gguf --mmproj mmproj.gguf -ngl 999 --host 127.0.0.1 --port 8003 --jinja
# then, for the Rails app:
OCR_LONG_SERVICE_URL=http://127.0.0.1:8003/v1
```
