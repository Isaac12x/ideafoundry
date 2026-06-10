FROM python:3.12-slim

ARG WHISPER_MODEL=Systran/faster-whisper-base.en
ENV WHISPER_MODEL=${WHISPER_MODEL} \
    VOICE_ID_MODEL_PATH=/models/whisper-base.en \
    VOICE_ID_DEVICE=cpu \
    VOICE_ID_COMPUTE_TYPE=int8 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN python - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=os.environ.get("WHISPER_MODEL", "Systran/faster-whisper-base.en"),
    local_dir=os.environ.get("VOICE_ID_MODEL_PATH", "/models/whisper-base.en"),
    local_dir_use_symlinks=False,
)
PY

COPY app.py .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
