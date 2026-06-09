---
name: update-excalidraw-package
description: Use when updating Idea Foundry's @excalidraw/excalidraw dependency while keeping the embedded drawing editor local-only and free of upstream Excalidraw/Firebase connector secrets.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [ideafoundry, excalidraw, dependency-update, local-only, secrets]
    related_skills: []
---

# Update Excalidraw Package

## Overview

Idea Foundry embeds Excalidraw as a local drawing editor. The app should use the Excalidraw React component and export helpers, but it must not ship upstream Excalidraw connector configuration for Firebase, collaboration, AI, JSON upload, or Excalidraw app/library handoff backends.

The key guardrails are:

- Keep `@excalidraw/excalidraw` current in both npm and Yarn lockfiles.
- Build through `esbuild.config.mjs`, which includes the `excalidraw-local-only` plugin.
- Verify the generated bundle contains no Google API keys or upstream connector endpoints.
- Keep the React component configured as local-only (`isCollaborating={false}`, `aiEnabled={false}`, `validateEmbeddable={false}`, and connector-like canvas actions disabled).

## When to Use

Use this skill when:

- GitHub secret scanning flags `app/assets/builds/excalidraw_app`.
- Updating `@excalidraw/excalidraw` in Idea Foundry.
- Rebuilding Excalidraw assets after package updates.
- Reviewing whether the embedded editor can call Excalidraw/Firebase/AI/collaboration/library services.

Do not use this skill to add Excalidraw collaboration, remote library publishing, AI features, or app.excalidraw.com handoff. Those are intentionally out of scope for Idea Foundry's local drawing editor.

## Update Workflow

1. Confirm repo state:

   ```bash
   cd /home/devuser/ideafoundry
   git status --short
   git branch --show-current
   git remote -v
   ```

2. Check the latest package version:

   ```bash
   npm view @excalidraw/excalidraw version dist-tags --json
   ```

3. Update npm package metadata and `package-lock.json`:

   ```bash
   npm install @excalidraw/excalidraw@latest
   ```

4. Update `yarn.lock` too, because this repo currently carries both lockfiles:

   ```bash
   corepack yarn add @excalidraw/excalidraw@latest
   ```

   If plain `yarn` is unavailable, use `corepack yarn`. Do not leave only one lockfile updated unless the project intentionally removes the other.

5. Confirm `app/javascript/excalidraw_app/index.tsx` still imports only the package component/CSS and keeps local-only props:

   ```tsx
   import { Excalidraw, exportToBlob } from "@excalidraw/excalidraw";
   import "@excalidraw/excalidraw/index.css";

   <Excalidraw
     isCollaborating={false}
     aiEnabled={false}
     validateEmbeddable={false}
     UIOptions={LOCAL_ONLY_UI_OPTIONS as any}
     renderTopRightUI={() => null}
     onLinkOpen={(_, event) => event.preventDefault()}
   />
   ```

6. Rebuild assets:

   ```bash
   npm run build
   ```

7. Verify the generated Excalidraw bundle is local-only:

   ```bash
   npm run verify:excalidraw-local-only
   ```

   This fails on case-sensitive Google API keys (`AIza...`) and known upstream connector endpoints such as Firebase, `oss-collab.excalidraw.com`, `oss-ai.excalidraw.com`, `json.excalidraw.com`, `app.excalidraw.com`, and the Excalidraw library backend.

8. Inspect the diff before committing:

   ```bash
   git diff -- package.json package-lock.json yarn.lock esbuild.config.mjs app/javascript/excalidraw_app/index.tsx app/assets/builds/excalidraw_app scripts/check_excalidraw_bundle.mjs .hermes/skills/update-excalidraw-package/SKILL.md
   git status --short
   ```

## How the Local-Only Build Guard Works

`esbuild.config.mjs` scans `node_modules/@excalidraw/excalidraw/dist/{prod,dev}` for generated env chunks containing `VITE_APP_FIREBASE_CONFIG`. During the Excalidraw app build, the `excalidraw-local-only` plugin aliases those chunks to a sanitized module whose connector values are blank:

- `VITE_APP_FIREBASE_CONFIG: "{}"`
- collaboration/AI/library/JSON/app URLs: `""`
- tracking: `"false"`
- Excalidraw Plus export public key: `""`

This keeps the bundled component usable locally without committing Excalidraw's upstream Firebase/client connector config into Idea Foundry's generated assets.

## Common Pitfalls

1. **Updating only `package.json`.** Always update lockfiles too. This repo currently has both `package-lock.json` and `yarn.lock`.

2. **Bypassing `esbuild.config.mjs`.** A direct or alternate bundler build can re-embed Excalidraw's upstream env chunk and resurrect GitHub secret scanning alerts.

3. **Trusting UI props alone.** Props such as `isCollaborating={false}` prevent runtime features, but they do not remove static upstream config from the bundle. The esbuild plugin and verification script are the static guard.

4. **Case-insensitive secret scans.** Random binary/base64 content can contain `AIZa`-like text. Google API keys are case-sensitive and start with `AIza`; use the verifier's case-sensitive regex.

5. **Forgetting Excalidraw CSS after package updates.** Newer package versions export `@excalidraw/excalidraw/index.css`; keep it imported so the editor renders correctly.

6. **Assuming Excalidraw chunk names are stable.** They are hashed. The esbuild plugin scans for chunks containing `VITE_APP_FIREBASE_CONFIG` instead of hardcoding a chunk filename.

## Verification Checklist

- [ ] `@excalidraw/excalidraw` is updated in `package.json`, `package-lock.json`, and `yarn.lock`.
- [ ] `npm run build` succeeds.
- [ ] `npm run verify:excalidraw-local-only` succeeds.
- [ ] No `AIza[0-9A-Za-z_-]{35}` string exists in `app/assets/builds/excalidraw_app`.
- [ ] No Excalidraw Firebase/collab/AI/JSON/app/library backend endpoints exist in `app/assets/builds/excalidraw_app`.
- [ ] The React embed still disables collaboration, AI, embeddables, external link opening, and connector-style canvas actions.
