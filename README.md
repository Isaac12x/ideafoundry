# Idea Foundry

<img width="1536" height="1024" alt="Idea Foundry application" src="https://github.com/user-attachments/assets/c1e2fc48-6a87-478c-b362-8288eefc6e9c" />

The local-first CRM and planner for ideas. Capture a thought in seconds, score and triage it, develop it with notes and research, then decide whether to build, license, park, or preserve it. Idea Foundry keeps the work on your machine and records how every idea changes over time.

> Idea Foundry is active software under active development. The workbench, notes, knowledge base, planning tools, local security, and agent controls run today; the IP platform, marketplace, collaboration network, and legacy system are the longer-term direction described in [VISION.md](VISION.md).

## What runs today

**Capture and intake** — Create ideas in the app or bring them in through email, API submissions, mobile pairing, Apple Notes, Notion, Google Keep, and Evernote exports. Unsaved work is retained locally across locks and interruptions.

**Lifecycle, scoring, and planning** — Move ideas through a structured lifecycle, define multiple weighted scoring systems, triage with multiple Kanban boards and named lists, and graduate selected ideas into planning or the optional build backlog.

**Knowledge base** — Work directly with local files and folders. Add favourites and custom icons, preview common formats, run bounded local filesystem AI jobs, and edit images, video, audio, PDFs, and HTML with checksum-addressed revision history.

**Notes and rich idea documents** — Keep threaded notes, drawings, calculations, todos, media, competitors, tools, reminders, and custom template fields beside each idea.

**Topology and discovery** — Browse ideas with filters, infinite scrolling, command-palette search, list views, and an interactive 3D graph of relationships and hierarchical categories.

**History and provenance** — Snapshot idea changes, compare or restore versions, retain activity records, hash inbound content, and distinguish local-agent work from human contributions.

**Local security** — Encrypt production databases with SQLCipher, store recovery secrets in the OS keychain when available, lock access with typing fingerprint, authenticator app, or local Voice ID, and throttle sensitive recovery routes.

**Local agent controls** — Queue questions from anywhere in the app, review recommendations as diffs, and grant scoped, revocable per-idea document tokens instead of exposing the whole vault.

**Exports and backups** — Export the workspace to open formats or encrypted archives, run scheduled backups and digests, and include user-owned attachments as first-class backup data.

## How it has grown

| Period | Milestone |
| --- | --- |
| February 2026 · v1.0 | Lifecycle, scoring, Kanban, topology, templates, version history, rich text, exports, and backups established the core workbench. |
| March 2026 · v1.2–1.3 | Email/API intake, local HTTPS, threaded notes, and calendar reminders expanded capture and development. |
| May 2026 · v1.4+ | SQLCipher, typing and voice locks, multiple boards and scorecards, local agents, scoped tokens, and note imports turned the workbench into a private vault. |
| June 2026 | Planning, command-palette search, infinite browsing, mobile pairing, file storage, activity provenance, and local OCR broadened daily use. |
| July 2026 · current | The knowledge base gained live filesystem workflows, local AI jobs, favourites, media controls, and revision-safe editing studios. |

See [CHANGELOG.md](CHANGELOG.md) for the complete release history and current unreleased work.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Ruby 3.4.5, Rails 8.1 |
| Database | SQLite3 in development, SQLCipher-encrypted SQLite in production |
| Background Jobs | Solid Queue |
| Frontend | Hotwire (Turbo + Stimulus), Importmap |
| 3D Graph | Three.js + 3d-force-graph (esbuild bundle) |
| Rich Text | TipTap 2.x via Action Text |
| Email | Resend + Action Mailbox |
| Real-time | ActionCable (WebSocket) |

## Install (macOS)

One command — installs all dependencies, configures the LaunchAgent, and starts the service:

```bash
git clone https://github.com/Isaac12x/ideafoundry.git idea-app
cd idea-app
bin/install
```

This handles: Homebrew, rbenv, Ruby 3.4.5, Node.js, Caddy, gems, npm deps, DB setup, asset precompilation, `/etc/hosts` entry, Apache httpd disable, and LaunchAgent registration. On startup, the LaunchAgent also starts the Docker/Podman Compose sidecar services when a container runtime is available. Requires `sudo` for hosts file and httpd changes.

Once running: **https://ideas.local:8443**

Logs: `/tmp/idea-app.out` and `/tmp/idea-app.err`

### Recommended macOS companion: LaunchControl

Idea Foundry runs more smoothly as an always-available local service when its LaunchAgent is easy to inspect and recover. Pair it with [LaunchControl](https://github.com/Isaac12x/launch-control), a native macOS control surface for user `launchd` services.

`bin/install` already creates the Idea Foundry plist in `~/Library/LaunchAgents`, so LaunchControl can discover it without replacing the installer. Use it to see whether Idea Foundry is loaded and running, inspect CPU and memory, tail the declared logs, and start, stop, or restart the service without memorizing `launchctl` commands. Its keep-running, dependency, schedule, and critical-service notifications are also useful for a local instance expected to stay available.

### Development

```bash
bin/dev              # starts Rails + esbuild watcher (dev mode)
BACKLOG_ENABLED=true bin/dev  # starts dev mode with the optional backlog enabled
```

### Already cloned?

```bash
bin/install
```

See [SETUP.md](SETUP.md) for Docker and advanced deployment options.

## Screenshots

_Coming soon._

## Design Philosophy

Your machine is the vault and source of truth. Capture should be immediate, sharing should be deliberate, agents should have narrow and revocable access, and every important change should remain attributable and recoverable. The current app is designed primarily for a local owner; collaboration is planned per idea rather than as a public social layer.

## License

This project is not currently licensed for redistribution. All rights reserved.
