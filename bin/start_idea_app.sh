#!/bin/zsh

# Startup script for idea-app (production)
# Used by LaunchAgent com.<username>.idea-app

set -e

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export RAILS_ENV=production
export PORT=3333

# Init rbenv
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
eval "$(rbenv init - zsh)"

cd "$APP_DIR"

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
