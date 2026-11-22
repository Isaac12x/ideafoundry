---
title: Install and first run
---

## Requirements

- macOS is the supported install path (`bin/install`). Linux works through Docker or by hand, with some features unavailable.
- Ruby 4.0.7 (rbenv or asdf), Node.js 20+, SQLite3.
- Docker or Podman is optional and only needed for the OCR and Voice ID services ([Local services](services.md)).

System tools (SQLCipher, libvips, Caddy, ffmpeg, ImageMagick, Ghostscript, pdftk, poppler, pandoc, tesseract, DjVuLibre, 7z, whisper, yt-dlp, Calibre, Chrome) are listed in [`infra/Brewfile`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/Brewfile). That file is the single source of truth.

## macOS

```bash
git clone https://github.com/Isaac12x/ideafoundry.git idea-app
cd idea-app
bin/install
```

`bin/install` installs Homebrew (if missing) and the Brewfile dependencies, Ruby, gems and npm packages, prepares the database, precompiles assets, adds `ideas.local` to `/etc/hosts`, disables the built-in Apache httpd, and registers and starts a LaunchAgent. It needs `sudo` for the hosts file and httpd.

- Keep the checkout outside `Desktop`, `Documents` and `Downloads`; launchd cannot reliably read scripts there. `~/Applications/IdeaFoundry/<name>` works.
- The installer prints the URL when done. The default is `https://ideas.local:8443`.
- Logs: `/tmp/<installation-name>.out` and `/tmp/<installation-name>.err`.
- If a Brewfile entry fails, the installer warns and continues; the related features show as unavailable. Rerun `brew bundle --file=infra/Brewfile`.

### Several installations

Give each clone a name. Each gets its own LaunchAgent, logs, Compose project, ports and HTTPS proxy.

```bash
bin/install personal
bin/install research
```

The default name is `idea-app` (ports 3333/8000/8001). Other names get derived ports. `bin/start_idea_app.sh <name>` or `IDEA_APP_INSTALLATION_NAME` selects an installation for the launcher.

## Linux and Docker

- Debian/Ubuntu: `apt-get install libsqlcipher-dev sqlcipher libvips`, plus the apt equivalents listed in the final stage of [`infra/Dockerfile`](https://github.com/Isaac12x/ideafoundry/blob/master/infra/Dockerfile). Calibre, whisper, yt-dlp and Chrome are not in the image; those features show as "not installed".
- Rails app in a container: `docker compose -f infra/docker-compose.yml --profile app up --build`. It maps to host port 3333 (override with `PORT`), persists data in `./storage`, and needs `config/master.key`. Health check: `http://localhost:3333/up`.
- Without the `app` profile, Compose runs only the sidecar services and you run Rails under launchd or systemd.
- Bare metal: set `RAILS_ENV=production` and `SECRET_KEY_BASE`, then `bin/rails db:prepare`, `bin/rails assets:precompile`, `bin/rails server -p 3333`, and `bin/jobs` in a separate process.

More detail: [SETUP.md](https://github.com/Isaac12x/ideafoundry/blob/master/SETUP.md).

## First launch

1. Open the URL the installer printed.
2. Go to **Settings > Security** (`/settings/security`).
3. Enter and confirm a strong database recovery passphrase. Save it in two separate places.
4. If you have plaintext production databases, stop the app and its job worker, then start the Database Encryption action. The app writes and verifies an encrypted temporary copy before atomically replacing each original. It never writes a plaintext backup; any failure before replacement leaves the original database untouched. You can also run `bin/rails db:encrypt_sqlite` while the app is stopped.
5. Optionally set up a typing lock, authenticator app, or Voice ID.

Important:

- The recovery passphrase is the encryption root. Without it, the encrypted database cannot be opened. Use the same passphrase when moving the database to another computer.
- By default the passphrase is stored in the OS keychain, with a file fallback outside the checkout. To choose a specific file path, set `IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE` before using the security page ([Configuration](configuration.md)).
- The optional Backlog feature mirrors items to `storage/backlog.md` in plaintext.

Command-line fallback if the UI is unavailable:

```bash
RAILS_ENV=production \
IDEA_FOUNDRY_RECOVERY_PASSPHRASE_FILE=/path/outside/passphrase.txt \
bin/rails db:encrypt_sqlite
```

Email intake is optional. Add Resend keys with `bin/rails credentials:edit` (see [SETUP.md](https://github.com/Isaac12x/ideafoundry/blob/master/SETUP.md)); the app works without them.

## Backups

Scheduled backups are configurable in Settings. For a manual backup run `bin/backup [destination_dir]` (default `backups/`). It snapshots the SQLite databases and archives `storage/` files.

## Updating

```bash
git pull
bin/install        # same installation name as before
```

Rerunning the installer is safe: it stops the old service, installs new dependencies, migrates, rebuilds assets and restarts. Rebuild service images only when their Dockerfiles changed ([Local services](services.md)).

## Uninstall

There is no uninstall script. To remove an installation by hand:

```bash
launchctl unload ~/Library/LaunchAgents/<plist name>.plist   # name printed by bin/install
rm ~/Library/LaunchAgents/<plist name>.plist
docker compose -f infra/docker-compose.yml down -v          # only if you ran sidecars
```

Then delete the checkout, and the `ideas.local` line in `/etc/hosts` if you no longer want it. Your data lives in `storage/`; back it up first. (`bin/idea_app_cleanup` is an internal helper that stops stale processes at startup, not an uninstaller.)
