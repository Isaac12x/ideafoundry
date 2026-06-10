# Idea Foundry

<img width="1536" height="1024" alt="" src="https://github.com/user-attachments/assets/c1e2fc48-6a87-478c-b362-8288eefc6e9c" />

A personal idea management system for entrepreneurs. Capture rough ideas, evolve them through a structured lifecycle, score and rank them, organize with kanban boards and hierarchical topologies, and visualize relationships in an interactive 3D graph.

## Features

**Idea Lifecycle** — Track ideas through 9 states: New → Triage → First Try / Second Try → Incubating (cool-off) → Validated → Shipped | Parked | Rejected. Automatic cool-off timers with scheduled reopening.

**Weighted Scoring** — Rate ideas on TRL, Difficulty, Opportunity, and Timing (0-10). Configurable scoring weights produce a composite score. Track score trends and history over time.

**Kanban Boards** — Organize ideas into custom lists with drag-and-drop reordering. Share entire lists via email.

**3D Topology Graph** — Interactive WebGL force-directed graph showing idea relationships and hierarchical categories. Real-time updates via ActionCable.

**Version Control** — Git-like version history for every idea. Snapshot on each save, diff comparison between versions, restore to any previous state.

**Email Ingestion** — Send ideas via email. Action Mailbox + Resend fuzzy-matches subjects to existing ideas or creates new ones. SHA3 integrity hashing for email-sourced content.

**Templates** — Define reusable idea templates with custom fields, sections, and tab layouts.

**Rich Text Editor** — TipTap-powered WYSIWYG editor with image uploads and file attachments.

**Exports & Backups** — Full workspace export as `.tar.gz` or AES-encrypted ZIP. Scheduled daily backups with email notifications.

**Digest Emails** — Configurable daily and weekly digests summarizing idea activity.

**Backlog (optional)** — Built-in task board for tracking build items with position ordering, completion toggling, and markdown checklist subitems. Disabled by default; set `BACKLOG_ENABLED=true` when building or running the app to enable it.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Ruby 3.4.5, Rails 8.0 |
| Database | SQLite3 (zero-config, file-based) |
| Background Jobs | Solid Queue |
| Frontend | Hotwire (Turbo + Stimulus), Importmap |
| 3D Graph | Three.js + 3d-force-graph (esbuild bundle) |
| Rich Text | TipTap 2.x via Action Text |
| Email | Resend + Action Mailbox |
| Real-time | ActionCable (WebSocket) |

## Install (macOS)

One command — installs all dependencies, configures the LaunchAgent, and starts the service:

```bash
git clone <repo-url> idea-app && cd idea-app && bin/install
```

This handles: Homebrew, rbenv, Ruby 3.4.5, Node.js, Caddy, gems, npm deps, DB setup, asset precompilation, `/etc/hosts` entry, Apache httpd disable, and LaunchAgent registration. On startup, the LaunchAgent also starts the Docker/Podman Compose sidecar services when a container runtime is available. Requires `sudo` for hosts file and httpd changes.

Once running: **https://ideas.local:8443**

Logs: `/tmp/idea-app.out` and `/tmp/idea-app.err`

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

This is a **single-user app** — there is no authentication system. It's designed to run locally or on a private server behind network-level access control. The focus is on providing a powerful, frictionless tool for one person to manage their ideas without the overhead of multi-tenancy.

## License

This project is not currently licensed for redistribution. All rights reserved.
