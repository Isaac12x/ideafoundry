# Setup

## Prerequisites

- **Ruby** 3.4.5 (use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/))
- **Node.js** 20+ and npm (for esbuild graph bundle)
- **SQLite3** (usually pre-installed on macOS/Linux)
- **libvips** (for image processing)
  - macOS: `brew install vips`
  - Debian/Ubuntu: `apt-get install libvips`

## Local Development Setup

```bash
# Clone the repo
git clone <repo-url> idea-foundry
cd idea-foundry

# Install dependencies
bundle install
npm install

# Create and migrate the database
bin/rails db:prepare

# (Optional) Load sample data
bin/rails db:seed

# Start the dev server (Rails + esbuild watcher)
bin/dev
```

This runs two processes via `Procfile.dev`:
- `web` — Rails server on port 3000
- `js` — esbuild watching `app/javascript/graph/` for changes

Open `http://localhost:3000`.

## Credentials

Rails encrypted credentials store sensitive config. To edit:

```bash
EDITOR="code --wait" bin/rails credentials:edit
```

Required keys:

```yaml
resend:
  api_key: re_xxxx           # Resend API key for outbound email
  inbound_address: xxxx       # Resend inbound email address

email_ingestion:
  sha3_key: xxxx              # HMAC key for integrity hashing

external_webhook:
  token: xxxx                 # Bearer token for webhook endpoint
```

Email features are optional — the app works fine without them.

## Docker

```bash
# Build and run
docker-compose up --build

# Or in detached mode
docker-compose up -d --build
```

The container:
- Runs in production mode on port 3000 internally
- Maps to port 3333 on the host (configurable via `PORT` env var)
- Persists data via `./storage` volume mount
- Requires `./config/master.key` to decrypt credentials

Customize the port:

```bash
PORT=8080 docker-compose up
```

Health check endpoint: `http://localhost:3333/up`

## Production (Bare Metal)

```bash
# Set environment
export RAILS_ENV=production
export SECRET_KEY_BASE=$(bin/rails secret)

# Prepare the database
bin/rails db:prepare

# Precompile assets
bin/rails assets:precompile

# Start the server
bin/rails server -p 3333

# Start background jobs (separate process)
bin/jobs
```

### macOS LaunchAgent

A LaunchAgent plist is included at `com.iamin.idea-app.plist` for auto-starting in production on macOS login. Adjust the paths in the plist to match your installation, then:

```bash
cp com.iamin.idea-app.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.iamin.idea-app.plist
```

## Database

SQLite3 with four database files in `storage/`:

| File | Purpose |
|------|---------|
| `development.sqlite3` | Main dev database |
| `test.sqlite3` | Test database |
| `production.sqlite3` | Production database |
| `queue.sqlite3` | Solid Queue job store |

Backups: The app has built-in scheduled backups (configurable in Settings). Manual backup is just copying the `storage/` directory.

## Email Setup (Optional)

1. Create a [Resend](https://resend.com) account
2. Add your API key to credentials (see above)
3. Configure an inbound email address in Resend
4. Set up Resend webhook to point to `https://your-domain/rails/action_mailbox/ingresses/resend/inbound_emails`
5. Configure notification preferences in the app's Settings page

## Background Jobs

Solid Queue handles background processing. Recurring jobs are defined in `config/recurring.yml`:

| Job | Schedule |
|-----|----------|
| Daily digest email | 7am daily |
| Weekly digest email | 8am Mondays |
| Scheduled backup | 2am daily |
| Queue cleanup | Hourly |

In development, Solid Queue runs in-process. In production, start it separately with `bin/jobs`.
