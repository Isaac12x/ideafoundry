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

## 2026-07-13 — Live knowledge-base filesystem and AI jobs

Branch: `feature/kb-live-filesystem-jobs` (stacked on `feature/kb-navigation-media-shortcuts` / PR #65)

### Delivered

- External file drops now copy browser-provided file bytes into the exact KB source/folder, preserve generic file types in the tree, avoid overwrites with numbered filenames, and update through Turbo without a page reload.
- URL-based file creation keeps its existing asynchronous downloader but now tracks the stable source path, renders progress inside the target folder, and refreshes the full tree through Turbo broadcasts plus a polling fallback for separate job processes.
- Root/folder icons can be changed by clicking the icon and choosing an emoji or locally stored image. Display settings provides the default for folders without overrides. Files, folders, and roots can be favourited with the adjacent star.
- The right-click menu now ends with a visually separated “Open in Finder” action, scoped to configured KB paths.
- Files and folders can be passed as bounded local context to an asynchronous AI job. Prompts can be typed or recorded, transcribed through the FluidVoice adapter, and sent only to a loopback local OpenAI-compatible inference server.
- Completed jobs write Markdown into the context folder’s `job_results/` directory. Failures write an error result there when possible and otherwise remain visible as an inline failed job row.
- Added database-backed path-stable preferences/jobs, local Active Storage icons/voice messages, symlink/path traversal guards, activity events, and lifecycle updates for preferences across rename, move, and delete operations.

### Runtime configuration

- `LOCAL_INFERENCE_BASE_URL` selects the local OpenAI-compatible endpoint (default `http://127.0.0.1:8080/v1`). Remote hosts are rejected.
- `LOCAL_INFERENCE_MODEL` selects its model (default `gpt-3.5-turbo`).
- `FLUIDVOICE_SERVICE_URL` selects a FluidVoice-compatible transcription endpoint; without it, the bundled local voice service configuration is used.

### Verification

- `PARALLEL_WORKERS=1 bin/rails test` — 695 tests, 2,696 assertions, all passing.
- All `test/javascript/*.mjs` suites pass.
- `bin/rails zeitwerk:check` — all application code eager-loads successfully.
- `yarn build` and `npm run verify:excalidraw-local-only` — passed.
- `git diff --check` — passed.
- The configured `bin/importmap audit` CI step could not run because this checkout has no `bin/importmap` executable; the Rails and bundled-command fallbacks are also unavailable. This predates the feature.

### Workspace note

The `graphify-out/` artifacts and rebuild lock/cache entries were already dirty before this task. They are refreshed as required but intentionally excluded from the feature commit.
