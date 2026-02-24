# Idea Foundry

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

**Backlog** — Built-in task board for tracking build items with position ordering and completion toggling.

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

## Quick Start

```bash
git clone <repo-url> idea-foundry
cd idea-foundry
bundle install && npm install
bin/rails db:prepare
bin/rails db:seed    # optional sample data
bin/dev              # starts Rails + esbuild watcher
```

Open `http://localhost:3000`.

See [SETUP.md](SETUP.md) for detailed setup instructions including Docker and production deployment.

See [DEVELOPMENT.md](DEVELOPMENT.md) for contribution guidelines and architecture overview.

## Screenshots

_Coming soon._

## Design Philosophy

This is a **single-user app** — there is no authentication system. It's designed to run locally or on a private server behind network-level access control. The focus is on providing a powerful, frictionless tool for one person to manage their ideas without the overhead of multi-tenancy.

## License

This project is not currently licensed for redistribution. All rights reserved.
