# Idea Foundry Agent

This repository is the idea-app-agent runtime for Idea Foundry's local app worker. It keeps the parts that matter for an agentic product loop:

- local OpenAI-compatible inference by default
- the tool loop in `run_agent.AIAgent`
- a constrained `idea-foundry` toolset that proxies Rails-owned domain tools
- a continuous daemon entrypoint for app-owned local work cycles
- compatibility shims for the older `webapp_agent` import path

The terminal CLI, TUI, editor adapter, release website, broad cloud inference provider catalog, and training/data-generation surfaces have been removed.

## Local Inference

The runtime expects an OpenAI-compatible local endpoint. By default it
targets `llama-server` on `http://127.0.0.1:8080/v1`.

Start llama.cpp's server with a tool-capable chat template:

```bash
llama-server -m /path/to/model.gguf --host 127.0.0.1 --port 8080 --alias gpt-3.5-turbo --jinja
```

```bash
export LOCAL_INFERENCE_BASE_URL=http://127.0.0.1:8080/v1
export LOCAL_INFERENCE_MODEL=gpt-3.5-turbo
export LOCAL_INFERENCE_API_KEY=local
```

Equivalent `HERMES_LOCAL_*` names are also accepted. For llama.cpp-specific
configuration, `LLAMA_SERVER_BASE_URL`, `LLAMA_SERVER_MODEL`, and
`LLAMA_SERVER_API_KEY` are accepted as aliases.

## Rails Tool Bridge

The Idea Foundry worker does not mutate app data directly. Rails owns reads,
writes, validation, locking, history, and audit logs through the local tool
bridge. The default bridge URL is
`https://ideas.local:8443/local-agent/tools`, matching the Caddy hostname and
TLS certificate used by the app. Set `IDEA_FOUNDRY_TOOL_BRIDGE_URL` only when
Rails runs somewhere else. Legacy local targets on `localhost:3000`,
`127.0.0.1:3000`, or `localhost:8443` are normalized to `ideas.local` so the
agent does not bypass Caddy's certificate hostname.

Rails may also launch the daemon with `IDEA_FOUNDRY_AGENT_SECRET` and
`IDEA_FOUNDRY_AGENT_RUN_ID` for private local-process trust and run tracking.

## Daemon

Run one local cycle:

```bash
bin/idea-foundry-agent --once
```

Run continuously while Rails settings keep the local agent enabled:

```bash
bin/idea-foundry-agent
```

The daemon checks `get_settings`, exits when disabled, runs cycles with the
`idea-foundry` toolset, records heartbeats through `record_event`, and sleeps
according to Rails `sleep_seconds`.

## Cycle API

Run the API with:

```bash
uvicorn idea_foundry_agent.api:app --host 0.0.0.0 --port 8000
```

Run a cycle:

```bash
curl -s http://localhost:8000/api/agent/cycle \
  -H 'content-type: application/json' \
  -d '{"instructions":"Run one local-agent cycle now."}'
```

The deprecated `/api/agent/turn` endpoint and `webapp_agent` package remain as
compatibility shims. New code should use cycle terminology.

## Idea Foundry Tools

The default worker toolset is `idea-foundry`:

- `get_settings`
- `list_work`
- `read_record`
- `update_idea`
- `create_note`
- `create_todo`
- `update_todo`
- `update_build_item`
- `approve_submission`
- `reject_submission`
- `transition_idea`
- `assign_list`
- `assign_topology`
- `create_fact`
- `create_maxim`
- `run_enrichment`
- `create_recommendation`
- `record_event`

Broad terminal, file, browser, web, and connector tools are not part of the
default Idea Foundry worker surface.

## Retained Compatibility

The repo still carries the upstream skill, plugin, MCP, messaging, and
connector surfaces for future opt-in expansion and compatibility with existing
tests/imports. They are not enabled by the Idea Foundry daemon by default.

Install optional connector dependencies as needed:

```bash
uv sync --extra connectors
```

## Tests

```bash
scripts/run_tests.sh
```
