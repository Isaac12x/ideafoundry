#!/bin/zsh

# Startup script for idea-app (production)
# Used by LaunchAgent com.<username>.idea-app

set -e

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export RAILS_ENV="${RAILS_ENV:-production}"
export PORT="${PORT:-3333}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-idea-app}"
export VOICE_ID_PORT="${VOICE_ID_PORT:-8000}"
export OCR_SERVICE_PORT="${OCR_SERVICE_PORT:-8001}"
export VOICE_ID_SERVICE_URL="${VOICE_ID_SERVICE_URL:-http://127.0.0.1:${VOICE_ID_PORT}}"
export OCR_SERVICE_URL="${OCR_SERVICE_URL:-http://127.0.0.1:${OCR_SERVICE_PORT}/extract}"
export OCR_SERVICE_TIMEOUT="${OCR_SERVICE_TIMEOUT:-900}"

# Init rbenv
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
eval "$(rbenv init - zsh)"

cd "$APP_DIR"

typeset -a COMPOSE_CMD

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

podman_available() {
  command -v podman >/dev/null 2>&1 || return 1
  podman info >/dev/null 2>&1 && return 0

  echo "==> Podman is installed but not running; trying to start the default machine..."
  podman machine start >/dev/null 2>&1 || return 1
  podman info >/dev/null 2>&1
}

detect_compose_cmd() {
  if [[ -n "${IDEA_APP_COMPOSE_CMD:-}" ]]; then
    COMPOSE_CMD=("${(@z)IDEA_APP_COMPOSE_CMD}")
    return 0
  fi

  if docker_available && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if docker_available && command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi

  if podman_available && podman compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(podman compose)
    return 0
  fi

  if podman_available && command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(podman-compose)
    return 0
  fi

  return 1
}

start_compose_services() {
  if detect_compose_cmd; then
    echo "==> Starting Docker/Podman compose sidecar services with: ${(j: :)COMPOSE_CMD} up -d --build"
    if "${COMPOSE_CMD[@]}" up -d --build; then
      echo "==> Compose sidecar services are starting."
    else
      echo "==> Compose sidecar startup failed; continuing without local sidecar services."
    fi
  else
    echo "==> No running Docker/Podman compose runtime found; skipping local sidecar services."
  fi
}

start_compose_services

# Ensure DB is ready when it can be opened without browser recovery input
DB_PREPARE_OUTPUT="$(bin/rails db:prepare_if_unlocked)"
printf '%s\n' "$DB_PREPARE_OUTPUT"
if [[ "$DB_PREPARE_OUTPUT" == *"Skipping db:prepare"* ]]; then
  DB_LOCKED=1
else
  DB_LOCKED=0
fi

# Precompile assets if missing or stale
bin/rails assets:precompile

# Start SolidQueue in background when the DB is already unlocked
if [[ "$DB_LOCKED" == "1" ]]; then
  echo "==> Database locked; skipping SolidQueue until the recovery passphrase unlocks encrypted data."
  JOBS_PID=""
else
  bin/jobs &
  JOBS_PID=$!
  echo "$JOBS_PID" > tmp/pids/solid_queue.pid
fi

# Start Caddy reverse proxy (HTTPS on ideas.local → localhost:$PORT)
caddy start --config "$APP_DIR/Caddyfile" --pidfile "$APP_DIR/tmp/pids/caddy.pid"
CADDY_PID=$(cat "$APP_DIR/tmp/pids/caddy.pid" 2>/dev/null)

cleanup() {
  echo "==> Shutting down Caddy..."
  caddy stop --config "$APP_DIR/Caddyfile" 2>/dev/null || true
  if [[ -n "$JOBS_PID" ]]; then
    echo "==> Shutting down SolidQueue (PID $JOBS_PID)..."
    kill "$JOBS_PID" 2>/dev/null || true
    wait "$JOBS_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Start Puma (foreground — LaunchAgent manages the process)
bin/rails server -p $PORT
