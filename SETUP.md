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

When Rails runs directly under launchd/systemd, point it at those host-side services:

```bash
export VOICE_ID_SERVICE_URL=http://127.0.0.1:8000
export OCR_SERVICE_URL=http://127.0.0.1:8001/extract
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

Backups: The app has built-in scheduled backups (configurable in Settings). Manual backup is just copying the `storage/` directory.

### Local encryption model

Production uses SQLCipher for the primary and Solid Queue SQLite files. This is the protection that matters when the threat is “someone opens `storage/production.sqlite3` with plain `sqlite3`.” A normal SQLite CLI should see an unreadable encrypted file, not tables or user content.

The encryption root is a user-held recovery passphrase/key, not Rails credentials, `secret_key_base`, `config/master.key`, or a fixed Docker secret. Typing lock and local Voice ID are only convenience/security gates after the app has been unlocked with the recovery secret; they are not the only cryptographic unlock.

The same recovery secret is also used to derive an app-level AES-GCM key for especially sensitive settings stored inside the database:

- Typing fingerprint templates
- Voice ID fingerprint templates
- Authenticator app secrets

Generate a strong passphrase/key and save it somewhere outside the app checkout, outside `storage/`, and outside `config/master.key`:

```bash
openssl rand -base64 32 > /path/outside/idea-foundry-recovery-passphrase.txt
chmod 600 /path/outside/idea-foundry-recovery-passphrase.txt
```

Run Docker Compose with the file path, not the secret value:

```bash
IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE=/path/outside/idea-foundry-recovery-passphrase.txt docker compose up --build
```

Use the same recovery passphrase file when moving the encrypted database to another computer. Without it, the app cannot open the SQLCipher database and cannot decrypt protected security templates.

If you already have plaintext production SQLite files, run the app-owned migration command before `db:prepare`:

```bash
RAILS_ENV=production \
IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE=/path/outside/idea-foundry-recovery-passphrase.txt \
bin/rails db:encrypt_sqlite
```

The command encrypts the SQLCipher-configured databases from `config/database.yml`, verifies the encrypted copies, replaces the plaintext files, and keeps plaintext backups outside the checkout by default in `../idea-app-sqlcipher-backups`. Set `IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR=/path/outside/app` to choose a different backup location. After you have verified your encrypted database, move long-term plaintext backups to secure offline storage or delete them according to your backup policy.

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
