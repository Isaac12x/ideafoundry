# Setup

## Prerequisites

- **Ruby** 3.4.5 (use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/))
- **Node.js** 20+ and npm (for esbuild graph bundle)
- **SQLite3** (usually pre-installed on macOS/Linux)
- **SQLCipher** (required for production/encrypted SQLite databases)
  - macOS: `brew install sqlcipher`
  - Debian/Ubuntu: `apt-get install libsqlcipher-dev sqlcipher`
- **libvips** (for image processing)
  - macOS: `brew install vips`
  - Debian/Ubuntu: `apt-get install libvips`
- **Local media toolchain** (for knowledge-base video, audio, image metadata, and PDF editing)
  - macOS: `brew install ffmpeg imagemagick ghostscript pdftk-java poppler`
  - Debian/Ubuntu: `apt-get install ffmpeg imagemagick ghostscript pdftk-java poppler-utils`
  - `bin/install` installs missing tools automatically on macOS; the production Docker image includes them.

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

The repository includes Bundler config that builds the `sqlite3` gem against SQLCipher. If production database tasks fail with `SQLite3 gem is not linked with SQLCipher`, install SQLCipher and rerun `bundle install` so Bundler compiles the source gem instead of using a precompiled plain-SQLite gem.

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

By default, compose now runs only the associated sidecar services so the Rails app can be supervised separately by launchd/systemd:

```bash
# Build and run only sidecar services: voice-id and OCR
docker compose up --build

# Or in detached mode
docker compose up -d --build
```

The sidecar services bind to localhost only:
- Voice ID: `http://127.0.0.1:8000` (configurable via `VOICE_ID_PORT`)
- OCR: `http://127.0.0.1:8001/extract` (configurable via `OCR_SERVICE_PORT`)

OCR uses Surya with a local `llama.cpp` inference backend. The OCR image downloads a
prebuilt `llama-server` release binary during `docker compose build` (no source compile).

The first OCR request downloads the Surya model into the `ocr-model-cache` compose volume
and can take several minutes.
The service returns complete plain text for saving plus Surya HTML blocks in metadata for
rendering extracted pages.

### On-demand knowledge extraction (long documents)

Short documents keep the synchronous Surya path above. Documents longer than
`OCR_LONG_DOC_PAGE_THRESHOLD` pages (default 10) — books, patents — are routed to
a heavy **Unlimited-OCR** backend that runs *on demand*: started when an
extraction is enqueued and stopped after `OCR_LONG_IDLE_TIMEOUT` seconds of
idle. Output is parsed markdown kept beside the source — written next to the
book in its KB folder, or attached to the idea (and mirrored into attachment
search + enrichment). Extractions run on the isolated `long_ocr` Solid Queue
worker so they never block normal jobs. You can also force the heavy path from
the UI with **Extract knowledge**.

Backend selection (`OCR_LONG_BACKEND=auto|vllm|llamacpp|remote`):

- **vllm** — NVIDIA box, recipe image (`unlimited-ocr` compose service, `gpu` profile).
- **llamacpp** — Apple Silicon / CPU port via `llama-server` (`unlimited-ocr-llama`); see `long_ocr_service/README.md`.
- **remote** — set `OCR_LONG_SERVICE_URL` to an already-running endpoint (no lifecycle management).

```bash
# Build the on-demand backends (kept out of the default graph):
docker compose --profile gpu build unlimited-ocr-llama
```

Lifecycle management drives `docker compose` and therefore needs docker CLI
access on whatever host runs the `long_ocr` worker (host launchd run, a mounted
docker socket, or a remote backend).

When Rails runs directly under launchd/systemd, `bin/start_idea_app.sh` starts compose sidecars in the background **without blocking Rails**. Sidecar startup uses existing images only (`docker compose up -d --no-build` per service); it does not rebuild OCR on every boot. Voice ID and OCR are optional — if a sidecar image is missing or fails to start, the app still comes up and only that feature is unavailable until you build or fix the service manually.

Sidecar logs: `log/compose-sidecars.log`. Useful environment variables:

| Variable | Purpose |
|----------|---------|
| `IDEA_APP_SKIP_COMPOSE=1` | Skip compose entirely |
| `IDEA_APP_COMPOSE_BUILD=1` | Rebuild images during startup (slow; OCR is memory-heavy) |
| `IDEA_APP_COMPOSE_CMD` | Override compose command detection |

Build sidecars manually when needed:

```bash
docker compose build voice-id
docker compose build --no-cache ocr   # first build or after Dockerfile changes
docker compose up -d --no-build voice-id ocr
```

The script uses the first available running runtime from `docker compose`, `docker-compose`, `podman compose`, or `podman-compose`. It also points Rails at the host-side service URLs:

```bash
export VOICE_ID_SERVICE_URL=http://127.0.0.1:8000
export OCR_SERVICE_URL=http://127.0.0.1:8001/extract
export OCR_SERVICE_TIMEOUT=900
```

If you do want compose to run the Rails app too, opt into the `app` profile:

```bash
# Build and run sidecars plus the Rails app container
docker compose --profile app up --build

# Or in detached mode
docker compose --profile app up -d --build
```

The app container:
- Runs in production mode on port 3000 internally
- Maps to port 3333 on the host (configurable via `PORT` env var)
- Persists data via `./storage` volume mount
- Requires `./config/master.key` to decrypt credentials

Customize the app container port:

```bash
PORT=8080 docker compose --profile app up
```

Health check endpoint when the app container is running: `http://localhost:3333/up`

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

Backups: The app has built-in scheduled backups (configurable in Settings). Manual backups should use `bin/backup`, which snapshots SQLite safely and archives local Active Storage files from `storage/` so uploaded files stay in the same backup set as database records. See `docs/file-storage.md` for the file storage contract.

### Local encryption model

Production uses SQLCipher for the primary and Solid Queue SQLite files. This is the protection that matters when the threat is “someone opens `storage/production.sqlite3` with plain `sqlite3`.” A normal SQLite CLI should see an unreadable encrypted file, not tables or user content.

The encryption root is a user-held recovery passphrase/key, not Rails credentials, `secret_key_base`, `config/master.key`, or a fixed Docker secret. Typing lock and local Voice ID are only convenience/security gates after the app has been unlocked with the recovery secret; they are not the only cryptographic unlock.

The same recovery secret is also used to derive an app-level AES-GCM key for especially sensitive settings stored inside the database:

- Typing fingerprint templates
- Voice ID fingerprint templates
- Authenticator app secrets

Start Compose without a recovery passphrase environment variable; the passphrase is configured from the app UI, not from `.env` or Compose secrets:

```bash
docker compose up --build
```

If you already have plaintext production SQLite files, open `/settings/security`, enter and confirm a strong database recovery passphrase, and confirm you saved that passphrase in two separate places before starting the Database Encryption action. When no explicit path is configured, the app writes the passphrase to `storage/recovery_passphrase.key`, then encrypts the SQLCipher-configured databases from `config/database.yml`, verifies the encrypted copies, replaces the plaintext files, and keeps plaintext backups outside the checkout by default in `../idea-app-sqlcipher-backups`.

Use the same recovery passphrase when moving the encrypted database to another computer. Without it, the app cannot open the SQLCipher database and cannot decrypt protected security templates.

For advanced deployments that need the app to read/write the passphrase at a specific path, set `IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE=/path/outside/idea-foundry-recovery-passphrase.txt` in the Rails process environment before using `/settings/security`; do not add a required interpolation to `docker-compose.yml`, because Podman Compose evaluates it even when the Rails app profile is not selected.

Set `IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR=/path/outside/app` before starting the app to choose a different backup location. After you have verified your encrypted database, move long-term plaintext backups to secure offline storage or delete them according to your backup policy.

> ⚠️ **Backlog Markdown backup is plaintext.** The Backlog feature continuously mirrors items to a human-editable Markdown file (default `storage/backlog.md`) and re-imports external edits to that file on load. This file is **not** SQLCipher-encrypted, so it exposes backlog titles, notes, and links in plaintext on disk. `storage/` is gitignored, but treat this file like any other plaintext export. Override the location with `config.x.backlog_backup_path` (e.g. point it at an offline/synced folder), or delete the file to disable round-tripping until the next mutation recreates it.

If the UI is unavailable, the same migration can still be run from the Rails task:

```bash
RAILS_ENV=production \
IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE=/path/outside/idea-foundry-recovery-passphrase.txt \
bin/rails db:encrypt_sqlite
```

## Email Setup (Optional)

1. Create a [Resend](https://resend.com) account
2. Add your API key to credentials (see above)
3. Configure an inbound email address in Resend
4. Set up Resend webhook to point to `https://your-domain/rails/action_mailbox/resend/inbound_emails`
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
