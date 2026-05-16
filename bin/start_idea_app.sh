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

# Ensure DB is ready
bin/rails db:prepare

# Precompile assets if missing or stale
bin/rails assets:precompile

# Start SolidQueue in background
bin/jobs &
JOBS_PID=$!
echo "$JOBS_PID" > tmp/pids/solid_queue.pid

# Start Caddy reverse proxy (HTTPS on ideas.local → localhost:$PORT)
caddy start --config "$APP_DIR/Caddyfile" --pidfile "$APP_DIR/tmp/pids/caddy.pid"
CADDY_PID=$(cat "$APP_DIR/tmp/pids/caddy.pid" 2>/dev/null)

cleanup() {
  echo "==> Shutting down Caddy..."
  caddy stop --config "$APP_DIR/Caddyfile" 2>/dev/null || true
  echo "==> Shutting down SolidQueue (PID $JOBS_PID)..."
  kill "$JOBS_PID" 2>/dev/null || true
  wait "$JOBS_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Start Puma (foreground — LaunchAgent manages the process)
bin/rails server -p $PORT
