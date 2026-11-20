---
title: Development
---

Run from source, run the checks, and find your way around the repo. For everyday use see [Install](install.md).

## Run in development

```bash
bundle install && yarn install
bin/rails db:prepare
bin/dev
```

`bin/dev` runs [`Procfile.dev`](https://github.com/Isaac12x/ideafoundry/blob/master/Procfile.dev): Rails (`web`), the esbuild watcher (`js`) and the Solid Queue worker (`jobs`). It picks a free port starting at 3000. `PORT=4000 bin/dev` changes the starting port; `bin/dev -p 4000` requires an exact one. `BACKLOG_ENABLED=true bin/dev` enables the optional backlog. `bin/setup` prepares everything and starts `bin/dev`; `bin/setup --skip-server` only prepares.

Sample data: `bin/rails db:seed`. Console: `bin/rails console`.

## Tests and the full gate

```bash
bin/rails test                       # unit and integration
bin/rails test test/models/idea_test.rb:42
bin/rails test:system                # needs Chrome
bin/ci                               # full gate
```

`bin/ci` ([`config/ci.rb`](https://github.com/Isaac12x/ideafoundry/blob/master/config/ci.rb)) runs, in order: setup, RuboCop, importmap audit, `yarn build`, JavaScript tests (`test/javascript/*.mjs`), the Rails test suite, and a production eager-load boot check. Run it before sending a change. `test/brewfile_test.rb` fails if the app shells out to a tool missing from `infra/Brewfile`.

## Repo layout

| Path | Contents |
|------|----------|
| `app/` | Rails app: models, controllers, views, jobs, services; Stimulus controllers in `app/javascript/controllers/` |
| `app/javascript/` | Importmap controllers plus esbuild bundles (3D graph, KB viewers, editors) |
| `config/` | Routes, `database.yml`, `recurring.yml` (scheduled jobs), `ci.rb` |
| `db/` | Schema, migrations, seeds |
| `storage/` | SQLite databases and Active Storage files (gitignored) |
| `infra/` | Everything outside Rails: Brewfile, Dockerfile, Compose, Caddy, launchd template, `services/{ocr,long_ocr,voice_id}` |
| `test/` | Rails and JavaScript tests |
| `docs/guide/` | Markdown source of these public docs |

Key choices (details in [DEVELOPMENT.md](https://github.com/Isaac12x/ideafoundry/blob/master/DEVELOPMENT.md)): single-user app with no login (secured at the network and lock level); SQLite everywhere (SQLCipher in production); Hotwire with importmap, and esbuild only for heavy bundles; idea versions stored as JSON snapshots.

## Editing these docs

Pages are Markdown with a YAML `title` in `docs/guide/`. Preview the site locally with `bin/build-site`, which writes the result to `_site/`. Link between guide pages with relative `.md` links.

## Conventions

- New external CLI: add it to `infra/Brewfile`, the `infra/Dockerfile` final-stage apt list, and `PACKAGES` in `test/brewfile_test.rb`.
- New out-of-process service: `infra/services/<name>/` with a Dockerfile and README, registered in `infra/docker-compose.yml`, with its URL passed to Rails by an environment variable. Rails-side client code stays in `app/`.
- New feature: migration and model, controller, views, Stimulus controller, route, tests.
- Background jobs go in `app/jobs/`; recurring ones in `config/recurring.yml`.
- Missing optional tools should show as an unavailable feature, not an error.
- The embedded Excalidraw editor is pinned and refreshed monthly; see [CLAUDE.md](https://github.com/Isaac12x/ideafoundry/blob/master/CLAUDE.md).
