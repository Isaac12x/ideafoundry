# Local Voice ID

Idea Foundry's Voice ID flow does not depend on the browser's cloud speech-recognition API. The browser records a short microphone sample locally, posts the audio to Rails, and Rails forwards it to the bundled `voice-id` container in `docker-compose.yml`.

## Runtime architecture

- Browser: records audio with `MediaRecorder` and calculates a local RMS volume metric.
- Rails: receives `POST /typing-lock/voice-id/transcribe` and calls `LocalVoiceIdClient`.
- `voice-id` service: runs FastAPI + faster-whisper against an on-image Whisper model and returns the transcript.
- Rails: keeps storing only the derived Voice ID fingerprint; raw audio is not stored. The derived fingerprint is encrypted with the user recovery secret before it is persisted.

## Offline behavior

The default compose build downloads `Systran/faster-whisper-base.en` into the `voice-id` image at build time. After the image is built, Voice ID transcription runs inside the compose network and does not require Wi-Fi or any third-party runtime API.

To prebuild before going offline:

```bash
docker compose build voice-id web
```

Then run normally:

```bash
docker compose up
```

## Running Rails outside Docker

You can run the Rails app directly on the host while keeping bundled services in Compose:

```bash
docker compose up voice-id
bin/rails server
```

The `voice-id` container is published on `127.0.0.1:${VOICE_ID_PORT:-8000}`. A host-run Rails process can use:

```bash
VOICE_ID_SERVICE_URL=http://localhost:8000 bin/rails server
```

If `VOICE_ID_SERVICE_URL` is not set, `LocalVoiceIdClient` first tries the in-compose service name (`http://voice-id:8000`) and then falls back to `VOICE_ID_HOST_URL` or `http://localhost:8000`. This keeps the same code path working both inside Compose and on the host with Compose-managed side services.

## Configuration

- `VOICE_ID_SERVICE_URL` in the Rails container points to the internal service URL. Default in compose: `http://voice-id:8000`.
- `VOICE_ID_HOST_URL` overrides the automatic host fallback URL for Rails processes running outside Docker. Default: `http://localhost:8000`.
- `VOICE_ID_PORT` publishes the compose service on the host. Default: `8000`.
- `VOICE_ID_WHISPER_MODEL` overrides the faster-whisper model downloaded at image build time.
- `VOICE_ID_DEVICE` defaults to `cpu`; set to `cuda` only when the host compose setup has GPU support.
- `VOICE_ID_COMPUTE_TYPE` defaults to `int8` for CPU-friendly inference.
