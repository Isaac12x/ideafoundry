# Handoff

## 2026-07-22 — Project site hero and copy refinement

Branch: `feature/web`

### Delivered

- Reframed the landing-page copy around Idea Foundry's capture promise, private workbench, full provenance, and honest split between working software and the wider roadmap.
- Layered the existing still artwork beneath the hero film; the film autoplays once and crossfades back to the still on completion or playback error.
- Reduced-motion visitors now see the still immediately with autoplay disabled.
- Updated the page title, description, calls to action, section headlines, and supporting copy for clarity and consistency.

### Verification

- `tidy -errors -quiet docs/index.html` — passed with no HTML errors or warnings.
- Browser automation at 1512×982 and 390×844 — visually checked the page and confirmed no narrow-viewport horizontal overflow.
- Normal motion — video played from 0 to 10.04 seconds, fired its end state, and reached zero opacity over the poster.
- Reduced motion — video remained hidden and paused while the poster rendered immediately.
- `git diff --check` — passed.

## 2026-07-22 — Project history and macOS service documentation

Branch: `feature/web`

### Delivered

- Updated the GitHub Pages overview with an editorial build timeline from v1.0 through the current knowledge-base work.
- Marked the eight platform areas as built, expanding, in design, or roadmap so the working product is distinct from the long-term vision.
- Rewrote the README feature snapshot around the current capture, planning, knowledge-base, provenance, security, agent, and backup capabilities.
- Added a matching release-history summary, corrected the documented Rails/database stack, and replaced the install placeholder with the repository URL.
- Recommended pairing the installed macOS LaunchAgent with LaunchControl for service state, runtime stats, logs, controls, keep-running automation, and critical-service notifications.

### Verification

- `tidy -errors -quiet docs/index.html` — passed with no HTML errors or warnings.
- Headless Chrome at 1440×1000 and 500×844 — visually checked the release ledger; the narrow viewport has no horizontal overflow.
- Repository, asset, heading, and external GitHub link checks — passed.
- `git diff --check` — passed.
- `graphify update .` — completed successfully; generated `graphify-out/` changes remain outside the documentation commit.

## 2026-07-22 — App-styled dialogs and notes-tab safety

Branch: `fix/app-styled-dialogs`

### Delivered

- Added one accessible, promise-based Idea Foundry dialog for alerts, confirmations, and text prompts, with keyboard/backdrop cancellation, focus handling, reduced-motion support, queued requests, and amber/red semantic treatments.
- Routed every Turbo `data-turbo-confirm` action through the shared dialog and migrated the remaining direct browser alert/confirm/prompt calls in the editor, knowledge-base tree, drawings, and encrypted draft flow.
- Replaced the notes-toolbar browser prompt with a styled “Add note tab” form and added an explicit destructive confirmation before a custom tab and its local content are deleted.
- Corrected the custom note-tab markup so its tab and delete controls are separate, valid buttons with an accessible delete label.
- Kept the reusable prompt input structurally hidden outside prompt mode so security pages do not gain a dormant typed-input fallback.

### Verification

- `node --test test/javascript/*.mjs` — 26 tests, all passing.
- `PARALLEL_WORKERS=1 bin/rails test` — 713 tests, 2,808 assertions, all passing.
- `bin/rails test test/system/app_dialog_system_test.rb` — 2 headless Chrome tests, 14 assertions, all passing; exercised add, cancel-delete, confirm-delete, and Turbo-confirm flows.
- `RAILS_ENV=test bin/rails assets:precompile` and `bin/rails zeitwerk:check` — completed successfully.
- Add and destructive-dialog states were visually checked at 1400×1400 against the app’s Dark Forge design system.
- `git diff --check` — passed.

## 2026-07-13 — Knowledge-base media editing studios

Branch: `feature/kb-media-editors` (stacked on `feature/kb-live-filesystem-jobs`)

### Delivered

- Every knowledge-base file now exposes Edit in its file header and context menu, while the normal viewer remains free of editor controllers and controls until that explicit action is taken.
- Images open a full-resolution canvas studio with crop, free drawing, text annotation, rotation, horizontal/vertical flip, undo/reset, brightness, contrast, saturation, grayscale, and format-aware export.
- Video opens a local timeline editor with millisecond in/out points, scrubbing, speed, volume, fades, normalisation, mute, centred aspect crops, rotation/flips, resolution selection, and colour grading.
- Audio opens a decoded waveform editor with the same precise timeline, speed/volume/fades, loudness normalisation, and mono mixdown controls.
- PDFs support page removal/reordering through page sequences, whole-document rotation, lossless output, and print/ebook/screen optimisation. HTML has an in-app source editor. DOCX, XLSX, TIFF, and opaque formats use a revision-safe native-format replacement surface.
- Saves enqueue through Solid Queue, reject concurrent edits to the same path, process only with local binaries, atomically replace the selected file, and preserve its previous bytes under the source’s hidden `.ideafoundry-history/` tree.
- `KbMediaEdit` retains durable job/provenance state. Human activity records include the exact edit recipe, source/revision paths, and SHA-256 checksums before and after the edit.
- Fresh macOS installs and the production Docker image now include FFmpeg/ffprobe, ImageMagick, Ghostscript, pdftk, and Poppler; `SETUP.md` documents manual installation.

### Verification

- `PARALLEL_WORKERS=1 bin/rails test` — 707 tests, 2,789 assertions, 0 failures. Parallel runs intermittently hit the pre-existing native-KB directory-count race in `KbControllerTest`; that exact test passes alone, and one parallel full run also passed.
- `node --test test/javascript/*.mjs` — 21 tests, all passing.
- `bin/rails test test/system/kb_media_editor_system_test.rb` — headless Chrome verified dormant view mode, Edit activation, canvas load, controls, and Cancel return.
- Focused media suite — 13 tests, 101 assertions, all passing.
- Real local-tool smoke tests generated and edited MP4 and MP3 media, then probed the results; PDF page rotation plus screen optimisation also completed successfully. These caught and fixed output-time truncation for slowed media.
- `bin/rails zeitwerk:check` and `git diff --check` — passed.

### Runtime and storage notes

- Media rendering requires the separately running Solid Queue worker (`bin/jobs`) in production.
- Revisions deliberately live beside each KB source so its provenance travels with that source. The history directory is dot-prefixed and omitted from the KB tree.
- The pre-existing dirty `graphify-out/` artifacts remain outside the feature commit; they are refreshed after source changes as required.

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

## 2026-07-23 — Named side-by-side installations

Branch: `fix/named-installations`

### Delivered

- `bin/install [installation-name]` and `bin/start_idea_app.sh [installation-name]` now share validated installation-name parsing, with `idea-app` retained as the no-argument default and `IDEA_APP_INSTALLATION_NAME` supported for environment-driven launches.
- Each generated macOS LaunchAgent uses a name-scoped label, plist filename, stdout/stderr paths, and Docker/Podman Compose project name, preventing separate clones from taking over each other's service and container resources.
- Installer-time `PORT`, `VOICE_ID_PORT`, and `OCR_SERVICE_PORT` overrides are persisted in the generated plist so concurrently running clones can avoid host-port collisions.
- Non-default names now derive stable, disjoint Rails, sidecar, HTTPS, Caddy HTTP, and Caddy admin ports automatically and run an installation-local Caddy proxy, so a name alone is sufficient for side-by-side operation.
- The LaunchAgent passes its installation name back to the production startup script, and reinstalling one named service now stops that exact launchd label only.
- Recovery-aware production database preparation and asset compilation now receive the freshly generated secret key, preventing installation from failing immediately after plist generation or when encrypted data still needs its recovery passphrase.
- Installer reruns reuse an available Bundler executable instead of prompting to overwrite `bundle` and `bundler` on every run.
- macOS privacy-protected checkout locations are rejected before service registration, avoiding LaunchAgents that loop with exit code 127 because they cannot read scripts under Desktop, Documents, or Downloads.
- Explicit listener overrides are range-checked, and plist generation occurs only after database and asset setup succeeds so failed installs do not leave dead LaunchAgent files.
- README, setup guidance, changelog, and focused installation-name tests cover the new interface and parallel-install example.

### Verification

- `PARALLEL_WORKERS=1 bin/rails test` — 725 tests, 2,860 assertions, all passing.
- Focused installation parser, derived-port, and installer wiring suite — 14 tests, 72 assertions, all passing, including invalid name, port, and protected-path rejection.
- `zsh -n` — shared helper, installer, and production startup script all parse successfully.
- Rendered a `research` LaunchAgent with separate ports and verified it with `plutil`; label, argument, Compose project, port, and log path all resolved to the named installation.
- Rendered and validated a named installation's isolated Caddy configuration and confirmed every derived `idea-test` listener port was available alongside the running legacy installation.
- Both entry points return usage status 64 for an invalid installation name before performing startup or installation work.
- `git diff --check` — passed.
- `graphify update .` — completed successfully. Pre-existing generated `graphify-out/` changes remain outside this feature commit.

## 2026-07-23 — Fresh-install recovery guard

Branch: `fix/named-installations-master`

### Delivered

- Missing and zero-byte production databases are treated as uninitialized first-run state, not encrypted data requiring recovery.
- The SQLCipher connection hook lets Rails prepare a zero-byte database as plaintext until the user explicitly enables database encryption in Security settings.
- Recovery and typing-lock screens no longer mount the workspace activity drawer, shared app dialog, or their Stimulus controller.
- Regression coverage distinguishes missing/empty databases from genuinely encrypted files and verifies the minimal recovery layout.

### Verification

- Focused SQLCipher and recovery layout suite — 21 tests, 64 assertions, all passing.
- `PARALLEL_WORKERS=1 bin/rails test` — 730 tests, 2,889 assertions, all passing.
- `bin/rails zeitwerk:check` — passed.
- Restarted the `idea-test` LaunchAgent and verified `https://ideas.local:40733/` returns HTTP 200 without a recovery redirect; both production databases were prepared with valid plaintext SQLite headers.
- Directly verified `/recovery-secret` omits the activity panel, app dialog, and activity Stimulus controller in the live rendered HTML.
- Added startup file-race handling after review so a database removed between existence and size checks is safely treated as missing.

## 2026-07-23 — Empty first-run workspace and activity drawer removal

Branch: `fix/empty-first-run`

### Delivered

- Fresh database seeding now creates only the default local user and leaves Kanban boards, lists, ideas, and memberships empty.
- Ideas, idea details/forms, and Planning no longer create a default Kanban board as a side effect of a page request.
- The new-column form can reuse an existing board without creating one on GET; an actual submitted Kanban column can still create its required default board.
- Removed the globally mounted Activity drawer, its Settings trigger, and the raw Activity/close/reload markup that appeared above the notes bar. The dedicated Activity audit page remains available from Settings.
- Added regression coverage for empty seeding, side-effect-free empty Ideas/Planning pages, and the absence of the global Activity drawer.

### Verification

- `PARALLEL_WORKERS=1 bin/rails test test/db/seeds_test.rb test/controllers/ideas_controller_test.rb test/controllers/lists_controller_test.rb test/controllers/recovery_secrets_controller_test.rb` — 61 tests, 244 assertions, all passing.
- `PARALLEL_WORKERS=1 bin/rails test` — 733 tests, 2,909 assertions, all passing.
- `node --test test/javascript/*.mjs` — 26 tests, all passing.
- `bin/rails zeitwerk:check` and `git diff --check` — passed.
- `graphify update .` — completed successfully.

### Workspace note

- The pre-existing dirty `graphify-out/` artifacts remain outside the feature commit and are refreshed after source changes as required.
