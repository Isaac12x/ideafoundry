# Handoff

## 2026-07-13 — Knowledge-base continuity and media controls

Branch: `feature/kb-navigation-media-shortcuts`

### Delivered

- Moved the keyboard-shortcuts helper into the notes bar at bottom right and changed its visible label from `?` to `/shortcuts/`.
- Added per-source collapse-all and uncollapse-all folder actions that update the existing persisted collapse state.
- Reopen the last selected KB document after a page reload using an encrypted, permanent browser cookie; stale selections safely fall back to the first available document.
- Show full filenames (including extensions) in the tree and a selected-file header with filesystem created and modified dates.
- Made image and video previews focusable/selectable and copyable with either the header action or `Ctrl/Cmd+C`. Images use binary clipboard data where supported; video/unsupported browsers use rich-media and plain-link fallbacks.

### Verification

- `node --test test/javascript/*.mjs` — 14 passing.
- `bin/rails test` — 673 tests, 2,613 assertions, all passing.
- `RAILS_ENV=test bin/rails assets:precompile` — completed successfully and registered the new Stimulus controller.
- Headless Chrome at 1440×900 — visually checked the metadata/media layout; exercised collapse all, uncollapse all, and notes-bar shortcut placement through Selenium.
- `graphify update .` — completed successfully.

### Workspace note

The `graphify-out/` artifacts were already modified before this work began. They were refreshed as required but are intentionally not part of this feature commit so the pre-existing generated changes remain untouched.
