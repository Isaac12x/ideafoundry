import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from faster_whisper import WhisperModel

MODEL_PATH = os.environ.get("VOICE_ID_MODEL_PATH", "/models/whisper-base.en")
DEVICE = os.environ.get("VOICE_ID_DEVICE", "cpu")
COMPUTE_TYPE = os.environ.get("VOICE_ID_COMPUTE_TYPE", "int8")

app = FastAPI(title="Idea Foundry Local Voice ID", version="1.0.0")
model = WhisperModel(MODEL_PATH, device=DEVICE, compute_type=COMPUTE_TYPE)


@app.get("/health")
def health():
    return {"ok": True, "model_path": MODEL_PATH, "device": DEVICE}


@app.post("/transcribe")
async def transcribe(
    audio: UploadFile = File(...),
    duration_ms: str | None = Form(default=None),
    rms: str | None = Form(default=None),
):
    suffix = Path(audio.filename or "voice-id.webm").suffix or ".webm"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as temp_audio:
        temp_audio.write(await audio.read())
        temp_path = temp_audio.name

    try:
        segments, _info = model.transcribe(
            temp_path,
            language="en",
            beam_size=1,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        transcript = " ".join(segment.text.strip() for segment in segments).strip()
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Could not transcribe voice sample: {exc}") from exc
    finally:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass

    return {
        "transcript": transcript,
        "duration_ms": _float_or_none(duration_ms),
        "rms": _float_or_none(rms),
    }


def _float_or_none(value):
    try:
        return float(value) if value not in (None, "") else None
    except ValueError:
        return None
