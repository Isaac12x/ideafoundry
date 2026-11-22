# Agent Development Guide

This repository is now a webapp-facing agent runtime, not a CLI product.

## Retained Surfaces

- `run_agent.py`, `agent/`, `model_tools.py`, `toolsets.py`: core agent loop and tool orchestration.
- `webapp_agent/`: FastAPI adapter and local-inference runtime settings.
- `skills/` and `optional-skills/`: bundled skill library.
- `tools/skill_manager_tool.py`, `tools/skills_tool.py`, `tools/skill_usage.py`: skill reading, writing, and usage tracking.
- `agent/background_review.py` and `agent/curator.py`: self-improvement and skill maintenance loops.
- `tools/`, `plugins/`, `gateway/`: connector and integration surfaces.
- `plugins/model-providers/custom`: the only bundled inference provider profile.

## Removed Surfaces

Do not reintroduce the terminal CLI, TUI, editor adapter, release website, provider catalog, or training/data-generation utilities unless the product direction changes explicitly.

## Local Inference

Use an OpenAI-compatible local endpoint. The webapp runtime reads:

- `LOCAL_INFERENCE_BASE_URL`
- `LOCAL_INFERENCE_MODEL`
- `LOCAL_INFERENCE_API_KEY`

Defaults target `llama-server` local inference at `http://127.0.0.1:8080/v1`.
`LLAMA_SERVER_BASE_URL`, `LLAMA_SERVER_MODEL`, and `LLAMA_SERVER_API_KEY` are
also accepted as llama.cpp-specific aliases.

## Skills

Skills must stay enabled by default. The default toolset is `webapp-agent`, which includes `skills_list`, `skill_view`, and `skill_manage`. The skill creation nudge interval defaults to `1` so completed tool-using webapp turns can trigger the background skill review loop.

When editing skill behavior, preserve:

- bundled skills in `skills/`
- optional skills in `optional-skills/`
- agent-created skills under `$IDEA_APP_AGENT_HOME/skills/`
- background review writes through `skill_manage`
- curator backup/archive behavior

## Tests

Run:

```bash
scripts/run_tests.sh
```

Prefer focused tests around the webapp runtime, local inference settings, toolset membership, and skill/self-improvement behavior.
