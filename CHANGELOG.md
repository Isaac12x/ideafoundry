# Changelog

All notable changes to Idea Foundry will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
