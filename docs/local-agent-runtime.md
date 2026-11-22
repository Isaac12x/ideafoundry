# Embedded local agent runtime

Idea Foundry ships its local worker in [`agent_runtime/`](../agent_runtime/).
The Rails control plane remains the source of truth: the runtime asks Rails for
work through the local-agent tool bridge, and Rails applies writes with the
app's existing validation, history, and audit rules.

## Install Python dependencies

The runner uses its own ignored virtual environment when present. From the
repository root, install the locked runtime dependencies with uv:

```sh
uv sync --project agent_runtime --extra dev
```

Without uv, create the same environment and install the package:

```sh
python3 -m venv agent_runtime/.venv
agent_runtime/.venv/bin/python -m pip install -e 'agent_runtime[dev]'
```

The supervisor launches `agent_runtime/bin/idea-foundry-agent`. That wrapper
uses `agent_runtime/.venv/bin/python` when installed and otherwise falls back
to `python3`. It adds the runtime directory to `PYTHONPATH`, so no global
package install is required.

## Configure local inference

The default endpoint is an OpenAI-compatible local server at
`http://127.0.0.1:8080/v1`, model `gpt-3.5-turbo`, with API key `local`. Set
these in the app process environment to override them:

```sh
LOCAL_INFERENCE_BASE_URL=http://127.0.0.1:8080/v1
LOCAL_INFERENCE_MODEL=gpt-3.5-turbo
LOCAL_INFERENCE_API_KEY=local
```

The Rails supervisor passes `--run-id <AgentRun id>` and the matching
`IDEA_FOUNDRY_AGENT_RUN_ID`, plus the Rails URL and one-shot setting. The
daemon accepts these arguments and uses the run ID in bridge requests and
attributed events.

Run a non-mutating CLI startup check:

```sh
agent_runtime/bin/idea-foundry-agent --help
```

## Tests and coverage

Run the runtime suite with the embedded environment:

```sh
agent_runtime/.venv/bin/python -m pytest agent_runtime/tests
```

The bridge tests exercise HTTP request formatting, response decoding, and
error handling with a fake client; they do not contact Rails. The runtime
tests cover settings and the agent-runner adapter. The real `AIAgent` can be
constructed locally without calling a model endpoint; a model-backed cycle
requires a running local inference server and Rails.

The runtime retains its upstream attribution in `agent_runtime/LICENSE-UPSTREAM`
and its own MIT license in `agent_runtime/LICENSE`.
