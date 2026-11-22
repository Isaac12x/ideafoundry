# Agent Harness

This repository runs the Idea Foundry local agent harness. The harness is the
small runtime that connects three pieces:

- a local OpenAI-compatible model endpoint
- the agent loop in `run_agent.AIAgent`
- the Rails-owned Idea Foundry tool bridge

## Install

From the repository root:

```bash
uv sync --project agent_runtime --extra dev
```

If you need optional connector integrations too:

```bash
uv sync --project agent_runtime --extra dev --extra connectors
```

## Start Local Inference

By default the harness expects `llama-server` at
`http://127.0.0.1:8080/v1` using the model alias `gpt-3.5-turbo`.

```bash
llama-server -m /path/to/model.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --alias gpt-3.5-turbo \
  --jinja
```

The harness reads these environment variables:

```bash
export LOCAL_INFERENCE_BASE_URL=http://127.0.0.1:8080/v1
export LOCAL_INFERENCE_MODEL=gpt-3.5-turbo
export LOCAL_INFERENCE_API_KEY=local
```

`LLAMA_SERVER_BASE_URL`, `LLAMA_SERVER_MODEL`, and
`LLAMA_SERVER_API_KEY` are accepted as llama.cpp-specific aliases.

## What the Bridge Is

The bridge is an HTTP boundary between the agent and the Rails application.
The agent does not write Idea Foundry data directly. Instead, every domain
tool call is posted to Rails through the local bridge.

By default the agent uses `https://ideas.local:8443/local-agent/tools`,
matching the Caddy hostname and TLS certificate used by the app. You only need
`IDEA_FOUNDRY_TOOL_BRIDGE_URL` when running Rails somewhere else.
Legacy local targets on `localhost:3000`, `127.0.0.1:3000`, or
`localhost:8443` are normalized to `ideas.local` so the agent does not bypass
Caddy's certificate hostname.

For example, when the model asks to call `list_work`, `update_idea`, or
`record_event`, the Python harness posts that tool name and JSON arguments to
Rails. Rails then performs the real read or write with its own validation,
locking, authorization, history, and audit logging.

This keeps the agent runtime replaceable and prevents two systems from owning
the same application state.

If the daemon logs `Connection refused` while calling `get_settings`, Rails is
not listening at the configured bridge URL. Start the Rails app first:

```bash
cd /path/to/ideafoundry
bin/start
```

Then confirm the bridge responds:

```bash
curl -i https://ideas.local:8443/local-agent/tools/get_settings \
  -H 'content-type: application/json' \
  -d '{}'
```

`IDEA_FOUNDRY_RAILS_URL=https://ideas.local:8443` is also accepted; the agent will
derive `/local-agent/tools` from it.

## Run One Cycle

Run one local-agent cycle and exit:

```bash
agent_runtime/bin/idea-foundry-agent --once --verbose
```

Run continuously while Rails settings keep the local agent enabled:

```bash
agent_runtime/bin/idea-foundry-agent --verbose
```

Useful daemon options:

```bash
agent_runtime/bin/idea-foundry-agent --help
```

## Why FastAPI Exists

FastAPI is the optional HTTP harness surface. It is useful when another local
process wants to trigger a cycle with a request instead of spawning the daemon
command.

Use the daemon when Rails wants a long-running worker process. Use the FastAPI
server when you want an HTTP endpoint for development, local orchestration, or
compatibility with older webapp callers.

Start the API:

```bash
uv run --project agent_runtime uvicorn idea_foundry_agent.api:app --host 127.0.0.1 --port 8000
```

Trigger a cycle:

```bash
curl -s http://127.0.0.1:8000/api/agent/cycle \
  -H 'content-type: application/json' \
  -d '{"instructions":"Run one local-agent cycle now."}'
```

The older `/api/agent/turn` endpoint still exists for compatibility, but new
callers should use `/api/agent/cycle`.

## Dependency Resolver Error

If `uv sync --project agent_runtime --extra dev` fails with an error like this:

```text
browser-use>=0.12.0 depends on rich==14.3.1
project depends on rich>=14.3.3,<15
requirements are unsatisfiable
```

the cause is a version conflict in `pyproject.toml`. The `browser-use` package
currently pins some shared runtime dependencies, so this project must allow
those pinned versions.

The project dependencies should include:

```toml
"rich>=14.3.1,<15",
"pydantic>=2.12.5,<3",
"openai>=2.16.0,<3",
"google-api-python-client>=2.188.0,<3",
"google-auth-oauthlib>=1.2.4,<2",
```

After changing it, refresh the lock file and sync:

```bash
uv lock
uv sync --project agent_runtime --extra dev
```
