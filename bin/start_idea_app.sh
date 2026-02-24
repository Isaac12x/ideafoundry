#!/bin/zsh

# Startup script for idea-app (production)
# Used by LaunchAgent com.iamin.idea-app

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

# Start SolidQueue in background
bin/jobs &
JOBS_PID=$!
echo "$JOBS_PID" > tmp/pids/solid_queue.pid

# Start Puma (foreground — LaunchAgent manages the process)
exec bin/rails server -p $PORT
