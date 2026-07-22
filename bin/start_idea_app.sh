#!/bin/zsh

# Startup script for a named Idea Foundry installation (production)
# Used by LaunchAgent com.<username>.<installation-name>

set -e

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$APP_DIR/bin/idea_app_installation"
INSTALLATION_NAME="$(idea_app_installation_name "$@")" || exit $?
export IDEA_APP_INSTALLATION_NAME="$INSTALLATION_NAME"
export RAILS_ENV="${RAILS_ENV:-production}"
export PORT="${PORT:-3333}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$INSTALLATION_NAME}"
export VOICE_ID_PORT="${VOICE_ID_PORT:-8000}"
export OCR_SERVICE_PORT="${OCR_SERVICE_PORT:-8001}"
export VOICE_ID_SERVICE_URL="${VOICE_ID_SERVICE_URL:-http://127.0.0.1:${VOICE_ID_PORT}}"
export OCR_SERVICE_URL="${OCR_SERVICE_URL:-http://127.0.0.1:${OCR_SERVICE_PORT}/extract}"
export OCR_SERVICE_TIMEOUT="${OCR_SERVICE_TIMEOUT:-900}"

# Init rbenv
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
eval "$(rbenv init - zsh)"

cd "$APP_DIR"

echo "==> Starting Idea Foundry installation '$INSTALLATION_NAME' (Compose project: $COMPOSE_PROJECT_NAME)."

typeset -a COMPOSE_CMD

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

podman_available() {
  command -v podman >/dev/null 2>&1 || return 1

  if ! podman info >/dev/null 2>&1; then
    echo "==> Podman is installed but not running; trying to start the default machine..."
    podman machine start >/dev/null 2>&1 || return 1
    podman info >/dev/null 2>&1 || return 1
  fi

  # Refresh DOCKER_HOST to the machine's live socket (guards against stale env after VM type change)
  local _sock
  _sock=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)
  [[ -n "$_sock" && -S "$_sock" ]] && export DOCKER_HOST="unix://${_sock}"
  return 0
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
  if [[ "${IDEA_APP_SKIP_COMPOSE:-}" == "1" ]]; then
    echo "==> IDEA_APP_SKIP_COMPOSE=1; skipping local sidecar services."
    return 0
  fi

  if ! detect_compose_cmd; then
    echo "==> No running Docker/Podman compose runtime found; skipping local sidecar services."
    return 0
  fi

  mkdir -p "$APP_DIR/log"
  local compose_log="$APP_DIR/log/compose-sidecars.log"
  local -a up_args=(-d)
  if [[ "${IDEA_APP_COMPOSE_BUILD:-}" == "1" ]]; then
    up_args+=(--build)
    echo "==> Starting compose sidecars in background with image rebuild (see $compose_log)."
  else
    up_args+=(--no-build)
    echo "==> Starting compose sidecars in background without rebuild (see $compose_log)."
    echo "==> Set IDEA_APP_COMPOSE_BUILD=1 to rebuild images on startup."
  fi

  # Sidecars are optional. Never block Rails on compose — OCR builds are slow and
  # often fail on memory-limited Docker hosts.
  (
    set +e
    for svc in voice-id ocr; do
      echo "==> $(date '+%Y-%m-%d %H:%M:%S') starting $svc"
      if ! "${COMPOSE_CMD[@]}" up "${up_args[@]}" "$svc"; then
        echo "==> $(date '+%Y-%m-%d %H:%M:%S') $svc unavailable; continuing without it."
      fi
    done
  ) >>"$compose_log" 2>&1 &
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

# HTTPS for ideas.local is handled by the system Caddy on :8443
# (/opt/homebrew/etc/Caddyfile → localhost:$PORT). Skip the app-local
# Caddy unless explicitly re-enabled for standalone runs.
if [[ "${IDEA_APP_SKIP_CADDY:-1}" == "1" ]]; then
  echo "==> IDEA_APP_SKIP_CADDY=1; using system Caddy for ideas.local:${PORT}."
else
  caddy start --config "$APP_DIR/Caddyfile" --pidfile "$APP_DIR/tmp/pids/caddy.pid"
fi

cleanup() {
  if [[ "${IDEA_APP_SKIP_CADDY:-1}" != "1" ]]; then
    echo "==> Shutting down Caddy..."
    caddy stop --config "$APP_DIR/Caddyfile" 2>/dev/null || true
  fi
  if [[ -n "$JOBS_PID" ]]; then
    echo "==> Shutting down SolidQueue (PID $JOBS_PID)..."
    kill "$JOBS_PID" 2>/dev/null || true
    wait "$JOBS_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Required on macOS: Puma forks workers and the ObjC runtime crashes otherwise
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# Start Puma (foreground — LaunchAgent manages the process)
bin/rails server -p $PORT
