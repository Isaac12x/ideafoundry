# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project uses semantic
versioning.

## [Unreleased]

### Added

- Added the `idea_foundry_agent` runtime package with cycle API, Rails tool bridge, system prompt, and continuous daemon entrypoint.
- Added agent harness run documentation covering local inference, the Rails bridge, FastAPI, and dependency sync troubleshooting.
- Added the constrained `idea-foundry` toolset for Rails-owned Idea Foundry domain tools.
- Added `bin/idea-foundry-agent` for local daemon debugging.
- Added `webapp_agent` with a FastAPI turn endpoint and local-inference runtime settings.
- Added focused tests for webapp runtime settings and API response shaping.

### Changed

- Converted `webapp_agent` into a compatibility wrapper around the Idea Foundry runtime.
- Defaulted the webapp local-inference endpoint to llama.cpp `llama-server` on port 8080.
- Defaulted the Rails bridge URL to Caddy's `https://ideas.local:8443` hostname so TLS validation matches the local certificate.
- Pointed the default Rails bridge URL at the Rails `local-agent` route and accepted Rails supervisor run arguments.
- Relaxed shared dependency bounds to allow the versions pinned by `browser-use`.
- Stopped sending Ollama-only request body options to llama.cpp custom endpoints.
- Reduced the repository to a webapp-facing agent runtime with local inference defaults.
- Kept skills, optional skills, self-improvement loops, plugin hooks, and connector tooling.
- Removed CLI/TUI/editor adapter/docs/training surfaces and the bundled cloud model provider catalog.
