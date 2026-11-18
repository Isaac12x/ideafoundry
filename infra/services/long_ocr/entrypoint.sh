#!/usr/bin/env bash
# Launches llama-server with a DeepSeek-OCR / Unlimited-OCR GGUF (+ mmproj),
# exposing an OpenAI-compatible /v1 endpoint that LongOcr::Client talks to.
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/models}"
mkdir -p "$MODEL_DIR"

MODEL_PATH="${OCR_LONG_MODEL_PATH:-$MODEL_DIR/model.gguf}"
MMPROJ_PATH="${OCR_LONG_MMPROJ_PATH:-$MODEL_DIR/mmproj.gguf}"

if [ ! -f "$MODEL_PATH" ]; then
  if [ -n "${OCR_LONG_MODEL_URL:-}" ]; then
    echo "[long_ocr] downloading model -> $MODEL_PATH"
    curl -fsSL "$OCR_LONG_MODEL_URL" -o "$MODEL_PATH"
  else
    echo "[long_ocr] ERROR: no model at $MODEL_PATH and OCR_LONG_MODEL_URL unset." >&2
    echo "[long_ocr] Provide a DeepSeek-OCR / Unlimited-OCR GGUF + mmproj — see README.md." >&2
    exit 1
  fi
fi

if [ ! -f "$MMPROJ_PATH" ] && [ -n "${OCR_LONG_MMPROJ_URL:-}" ]; then
  echo "[long_ocr] downloading mmproj -> $MMPROJ_PATH"
  curl -fsSL "$OCR_LONG_MMPROJ_URL" -o "$MMPROJ_PATH"
fi

ARGS=( --host 0.0.0.0 --port 8000 -m "$MODEL_PATH" -ngl "${LLAMA_NGL:-0}" -c "${LLAMA_CTX_SIZE:-8192}" --jinja )
if [ -f "$MMPROJ_PATH" ]; then
  ARGS+=( --mmproj "$MMPROJ_PATH" )
fi

echo "[long_ocr] starting llama-server ${ARGS[*]}"
exec /opt/llama.cpp/llama-server "${ARGS[@]}"
