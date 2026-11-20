---
title: Idea Foundry
---

Idea Foundry is a local-first CRM and planner for ideas. Capture a thought in seconds, score and triage it, develop it with notes and research, then decide whether to build, license, park, or preserve it. Everything runs on your machine, and every change to an idea is recorded.

Status: active development. The workbench, notes, knowledge base, planning, local security and agent controls run today. The IP platform, marketplace and collaboration are longer-term direction (see [VISION.md](https://github.com/Isaac12x/ideafoundry/blob/master/VISION.md)).

## What it does

- **Capture**: in the app, by email, API, mobile pairing, or imports from Apple Notes, Notion, Google Keep and Evernote.
- **Lifecycle and scoring**: structured lifecycle, weighted scoring systems, multiple Kanban boards and lists, planning.
- **Knowledge base**: work directly on local files and folders; preview common formats; edit images, video, audio, PDFs and HTML with revision history; local transcription and OCR.
- **Notes and idea documents**: threaded notes, drawings, todos, media, reminders, custom templates.
- **Discovery**: filters, command-palette search, an interactive 3D graph of relationships.
- **History**: version snapshots you can compare or restore, plus an activity record.
- **Local agents**: queue questions, review recommendations as diffs, grant scoped, revocable per-idea tokens.
- **Exports and backups**: open formats or encrypted archives, scheduled backups.

## Local-first and privacy

- Your machine is the vault and the source of truth. Nothing leaves without an explicit action.
- Production databases are encrypted with SQLCipher. The key is a recovery passphrase that you set and hold. See [Install](install.md).
- Locking uses typing fingerprint, authenticator app, or local Voice ID. These are access gates on top of the passphrase, not a replacement for it.
- OCR, transcription and Voice ID run locally. See [Local services](services.md). Voice ID audio is not stored.
- Agents are local and act only through scoped tokens you can revoke.
- Everything exports to open formats.

## Guide

| Page | Contents |
|------|----------|
| [Install](install.md) | Requirements, macOS installer, Docker/Linux notes, first run, updating |
| [Using the app](using.md) | Palette, find, knowledge base projects, licensing, privacy haze |
| [Configuration](configuration.md) | Environment variables by feature |
| [Local services](services.md) | OCR, long-document OCR, Voice ID, transcription |
| [Development](development.md) | Running from source, tests, repo layout |

Source: [github.com/Isaac12x/ideafoundry](https://github.com/Isaac12x/ideafoundry). Release history: [CHANGELOG.md](https://github.com/Isaac12x/ideafoundry/blob/master/CHANGELOG.md).

License: MIT, see [LICENSE](https://github.com/Isaac12x/ideafoundry/blob/master/LICENSE).
