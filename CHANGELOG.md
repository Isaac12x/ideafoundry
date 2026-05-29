# Changelog

All notable changes to Idea Foundry will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Right-click idea cards can add ideas to Kanban board columns or named lists.
- Backlog items can include multiple uploaded images with inline thumbnails.
- Static GitHub Pages project overview site and deployment workflow.
- Configurable page quote shown below the navigation bar.
- Backlog markdown checklist subitems with per-item toggles and remaining/total counts.
- Named lists alongside Kanban columns, including a Lists default-view setting.
- Scoped idea document tokens for agents, LLMs, and harnesses to update an idea's working document with history-tracked API changes.
- Downloadable per-idea agent skill markdown for sharing idea document API instructions with agents.
- Local Agent settings, audit records, app-domain tools, recommendations, and supervisor hooks for the app-owned Idea Foundry worker.
- Local Agent questions on the AI Agents settings page, with queued answers linked into the audit trail and app-wide database context available through the Rails tool bridge.
- Comprehensive idea history snapshots and restore support for calculations, drawings, enrichment metadata, todos, notes, tools, competitors, media, scores, and list/topology memberships.
- Multiple Kanban boards with board-scoped columns, idea placement, and drag-and-drop moves.
- Native `docs/kb/` markdown files are automatically included in the KB.
- Topology-triggered template fields, GitHub credential settings, and GitHub repository release tracking for software ideas.
- KB Maxims section for high-importance reminders alongside IPFs/BPFs.
- Markdown responses for scoped idea document API reads via Rails 8.1's native markdown renderer.
- Structured Rails event reporting for scoped idea document reads and updates.
- App-wide Ask Agent chat sidebar for queuing local-agent questions from any page.
- Inline local-agent recommendation hints on idea pages with full diff previews and collapsed addition/file review.
- Intake batch imports for Apple Notes, Notion, Google Keep, and Evernote exports with selectable folders before import.
- OS keychain-backed recovery passphrase storage with an external file fallback and legacy storage migration.
- Rack::Attack throttling for recovery secret and local upgrade endpoints.
- Active Storage upgrade migrations and idea TLDR persistence.
- Static 400 and unsupported-browser error pages with app icons.

### Changed

- Idea creation no longer asks for Kanban board or named-list placement; placement remains available after the idea exists.
- Updated the app to resolve Rails 8.1.3 and Puma 8, with Rails 8.1 local CI and framework-default upgrade prep.
- Adopted Rails 8.1 framework defaults and regenerated schema dumps with Rails 8.1 alphabetized column ordering.
- Inbound email now enters the submission intake queue by default, while explicit `[IDEA-id]` subjects still update existing ideas directly.
- Kanban idea cards no longer show tools or competitor summaries.
- Idea work tokens are now gated by a settings toggle and the idea page shows only one compact token control.
- Backlog is now disabled by default and requires `BACKLOG_ENABLED=true` when building or running the app.
- AI agent settings now live at `/settings/ai-agents` and no longer expose model or inference URL overrides.
- Ask Agent moved out of `/settings/ai-agents` into a bottom-right resizable overlay.
- On/off settings toggles now autosave without requiring an extra settings form submission.
- SQLCipher recovery keys can rekey to stronger scrypt defaults and plaintext migration backups are removed after encryption.
- Setup, development, production, and CI configuration now target the Rails 8.1 and SQLCipher app runtime.

### Fixed

- Local agent harness probes to `/local-agent/tools` now receive JSON tool discovery instead of falling through to the app catch-all.
- Resend inbound email setup now uses the mounted `/rails/action_mailbox/resend/inbound_emails` webhook route.
- Backlog edit, delete, and completion streams now preserve item context and refresh counts/empty states.
- KB now fills the viewport below the app header and IPFs/BPFs content is centered within its panel
- Typing lock failed attempts now persist the real score in the database, hide the retry box during cooldown, and keep prompt words intact when wrapping.
- Unsaved edits on existing ideas are now encrypted locally and can be restored after the app locks.
- Idea index and topology cards once again expose enabled structured-entry quick add summaries.
- Multi-file media uploads from the idea edit page now create one history entry per upload batch instead of one per file.
- Missing saved KB folders remain listed as unavailable so the path can be updated.
- Idea media controls now keep Ask Agent out of navigation, show extracted attachment parts in the form sidebar, and separate image thumbnails from document attachments.
- Development now uses its own Solid Queue database so encrypted production queue data does not break local page loads.
- User settings are normalized after security-settings encryption so local security lock checks do not crash on double-encoded settings.

### Security

- Persisted recovery passphrases are moved out of app-local storage into platform secure storage when available.
- SQLCipher and recovery-secret configuration values are filtered from logs.

## [1.4.0] - 2026-05-12

### Added

- Typing fingerprint lock with inactivity timeout, manual locking, and optional authenticator app verification
- Idea index list view toggle with compact score rows
- Configurable idea detail tabs, including structured tool and competitor entries
- Idea-attached Excalidraw drawings with hero and attachment roles
- Auto-draft idea creation with orphaned draft cleanup
- Archived ideas view with restore support and idea search
- Web enrichment workflow for idea competitors, market context, and resources
- `.btn-xs` size variant for extra-small inline action buttons

### Changed

- Typing fingerprint enrollment and unlock now submit automatically after a complete matching sample is captured
- Standardized button sizes across the app for visual consistency
- Scheduled backup notifications now use the configured backup recipient and enqueue email delivery
- Recurring digest jobs now accept scheduler positional arguments

### Fixed

- Typing lock timeout now counts from the last recorded activity instead of the original unlock time
- Typing lock failures now show a decoy score response while successful unlocks transition through a top-of-page Three.js lock animation
- Typing lock unlock submissions now bypass Turbo so successful matches can render the transition and continue to the requested page
- Drag-scrolled tab rows now reset cleanly when the window loses focus
- Scoring system now always produces scores in 0.0–10.0 range instead of -1.0–9.0
- Idea search filters now use SQLite-compatible case-insensitive matching
- KB and IPFs/BPFs tabs now share the same full-height page layout

## [1.3.0] - 2026-03-28

### Added

- Threaded notes system for ideas with collapsible tree UI
- Calendar reminder UI with .ics download and Google Calendar links
- Calendar reminder design specification

## [1.2.0] - 2026-03-24

### Added

- Intake submission system with email ingestion and fuzzy matching
- API key management for external submissions
- Caddy HTTPS reverse proxy configuration
- One-line installer with templatized plist for any user

### Fixed

- SQLite locking under concurrent access
- Rack deprecation warnings

## [1.1.0] - 2026-03-16

### Added

- Todo checklist per idea
- Backlog description list rendering
- README documentation

### Fixed

- Email buttons mismatch and functionality
- Ideas restricted to a single list
- Color picker
- Image rendering
- Various UI gremlins

### Security

- Bumped nokogiri from 1.18.10 to 1.19.1
- Bumped rack from 3.2.1 to 3.2.5
- Bumped uri from 1.0.3 to 1.0.4
- Bumped esbuild from 0.20.2 to 0.25.0

## [1.0.0] - 2026-02-24

### Added

- Idea lifecycle tracking with 9 states (spark through archived)
- Weighted scoring system (TRL, Difficulty, Opportunity, Timing)
- Kanban boards with drag-and-drop list management
- 3D topology graph with idea relationships
- Version history with git-like snapshots and diffs
- Rich text editing with TipTap and image uploads
- Image editor with paint, crop, undo, and reset
- Custom templates with draggable field definitions
- Build backlog with prioritized task tracking
- Export and backup system
- Dark Forge theme with editorial typography

[unreleased]: https://github.com/Isaac12x/ideafoundry/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/Isaac12x/ideafoundry/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Isaac12x/ideafoundry/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Isaac12x/ideafoundry/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Isaac12x/ideafoundry/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Isaac12x/ideafoundry/releases/tag/v1.0.0
