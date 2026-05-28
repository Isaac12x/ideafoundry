# Local Idea Foundry Agent

## Goal

Idea Foundry should run a continuous local LLM worker that acts as an app-specific agent. The agent should keep discovering useful work inside the app, decide what to do next, act through app-owned tools, record what happened, and continue while the setting is enabled.

The worker is based on the sibling Hermes-derived runtime at `/Users/iamin/Sync/code@business/idea-app-agent`, but it should be renamed and reshaped around Idea Foundry instead of remaining a general webapp chat harness. Hermes remains the model/tool execution engine. The runner, prompts, tools, loop policy, and memory become Idea Foundry-specific.

## Non-Goals

- Do not require user-managed API tokens for the local agent.
- Do not make the local agent an external bearer-token client of `/api/v1/ideas/:id/document`.
- Do not remove existing idea work tokens. They remain useful for external agents and harnesses.
- Do not give the model direct database access. Rails owns all reads, writes, validation, locking, version history, and audit logs.

## Current Context

The Rails app already has:

- Single-user app ownership through `ApplicationController#set_user`.
- Settings stored in `User#settings`.
- Solid Queue for background jobs.
- Idea document API and `IdeaAgentToken` for external scoped access.
- Version history through `Idea#create_version` and `RecordsIdeaHistory`.
- First-class work surfaces: ideas, submissions, todo items, notes, build items, facts, maxims, lists, topologies, attachments, OCR, GitHub repository tracking, enrichment jobs, and lifecycle state transitions.

The sibling agent repo already has:

- `run_agent.py` with `AIAgent`, the core Hermes tool loop.
- `webapp_agent/runtime.py` and `webapp_agent/api.py`, a generic FastAPI adapter around local inference.
- `toolsets.py` with a `webapp-agent` toolset.
- Local OpenAI-compatible inference defaults.

## Architecture

The feature has two cooperating parts:

1. Rails local agent control plane
   - Stores settings.
   - Starts and stops the worker.
   - Exposes app-domain tools to the runner.
   - Applies all mutations.
   - Records every action, recommendation, error, and run heartbeat.

2. Idea Foundry agent runner
   - Renamed from the generic webapp harness to an Idea Foundry-specific runner.
   - Uses Hermes `AIAgent` for model calls and tool execution.
   - Runs continuously while enabled.
   - Uses only Idea Foundry domain tools by default.
   - Sleeps with backoff when no valuable work is available, then asks again.

The runner is local infrastructure, not a remote client. It does not receive a per-idea token and does not ask the user to paste credentials. Rails starts it with local process trust and a private local bridge, then Rails tools enforce the current settings on every action.

## Settings

Add a new Settings page: `Settings > Local Agent`.

Store settings under `settings["local_agent"]`:

- `enabled`: when true, the local agent may run continuously.
- `destructive_actions_enabled`: when true, the local agent may directly perform destructive or terminal actions.
- `sleep_seconds`: default delay between cycles when the agent has no immediate work.
- `max_actions_per_cycle`: cap on actions before a checkpoint heartbeat.
- `model`: optional local model override.
- `base_url`: optional local inference endpoint override.

Defaults:

```ruby
{
  "enabled" => false,
  "destructive_actions_enabled" => false,
  "sleep_seconds" => 30,
  "max_actions_per_cycle" => 20
}
```

When `enabled` is false, Rails should stop launching the runner and should reject local agent tool calls that mutate app state.

When `destructive_actions_enabled` is false, destructive choices become recommendations instead of direct mutations.

## Autonomy Policy

Constructive actions are allowed when `enabled` is true:

- Improve idea descriptions.
- Add notes.
- Create or refine todo items.
- Add backlog/build item detail.
- Enrich idea metadata.
- Summarize attachments or OCR text into notes.
- Draft facts and maxims.
- Suggest list/topology organization.
- Prepare submission approval payloads.
- Recommend lifecycle transitions.

Destructive or terminal actions require `destructive_actions_enabled`:

- Reject a submission.
- Delete a submission, idea, note, todo, build item, fact, maxim, list, topology, attachment, or drawing.
- Mark an idea rejected or shipped.
- Archive or bulk cleanup records.
- Remove list/topology assignments in bulk.
- Overwrite substantial user-authored content without preserving the prior content in history.

If destructive actions are disabled, Rails creates an `AgentRecommendation` instead. The recommendation stores the target record, proposed action, reasoning, payload, risk level, and status. The UI lets the user approve, dismiss, or inspect it.

## Continuous Loop

The runner should not wait for user prompts. It runs this loop:

1. Ask Rails for current settings and a work batch with `list_work`.
2. Choose the highest-value next item.
3. Read enough context with domain tools.
4. Act or create a recommendation.
5. Record an action summary.
6. Ask for more work.
7. Sleep only when there is no useful work or when a cycle cap is reached.

The runner should preserve working memory between cycles, but Rails remains the source of truth. Each cycle should re-read current state before acting so it does not rely on stale model context.

## Work Discovery

`list_work` returns prioritized candidates across all app surfaces from day one:

- Pending submissions, including high priority and stale submissions.
- Ideas with blank, weak, or stale descriptions.
- Ideas in active lifecycle states that have no next todo.
- Ideas with pending todo items that need elaboration or grouping.
- Recent notes that imply missing todos or idea updates.
- Build items that are incomplete, stale, or have unchecked checklist items.
- Ideas with attachments whose OCR text has not been summarized.
- Facts or maxims that are missing links to relevant ideas.
- Lists and topologies that look underused or inconsistent.
- GitHub repositories that need tracking updates when GitHub settings are configured.
- Ideas with enrichment errors or stale enrichment metadata.
- Cool-off ideas whose timers expired or whose next step is missing.

The first implementation can use deterministic Rails heuristics for priority, then let the model choose among the returned candidates. Priority should favor high-impact work and avoid repeatedly cycling on the same target.

## Rails Domain Tools

Expose a small app-specific tool surface to the runner. Tool names should be explicit and stable:

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

All tools return structured JSON. Mutating tools validate:

- Agent is enabled.
- The target belongs to the single app user.
- The target still exists and has not changed in a conflicting way.
- Destructive autonomy is enabled when required.
- The action is within the tool's allowed schema.

Version history should be created for idea content changes. Notes and todos already have history hooks through `RecordsIdeaHistory`.

## Runner Changes

In `/Users/iamin/Sync/code@business/idea-app-agent`:

- Rename the generic `webapp_agent` package to `idea_foundry_agent`.
- Rename one-shot generic web API concepts from "turn" to "cycle"; use "daemon" only for the long-running process entrypoint.
- Keep `run_agent.AIAgent` as the low-level execution loop.
- Add an Idea Foundry system prompt that describes the app's entities, lifecycle, autonomy policy, and destructive-action setting.
- Replace the default `webapp-agent` toolset with an `idea-foundry` toolset.
- Add a continuous daemon entrypoint at `idea_foundry_agent/daemon.py`.
- Add a CLI wrapper at `bin/idea-foundry-agent` for local debugging.

The runner should not include broad file, terminal, browser, or connector tools by default. Those can remain available for future opt-in expansion, but the normal app worker should only use Rails domain tools plus model reasoning.

## Rails Process Management

Rails should own whether the runner is active:

- `LocalAgentSupervisorJob` checks settings and starts the runner if needed.
- A PID or heartbeat record prevents duplicate runners.
- The runner updates heartbeat timestamps.
- If heartbeat becomes stale while enabled, Rails may restart it.
- If `enabled` becomes false, Rails stops or lets the runner exit on the next settings check.

Do not wire the daemon into `Procfile.dev`, `bin/start`, or the LaunchAgent until process supervision and heartbeat tests pass. After that, development startup adds one `agent` process to `Procfile.dev`, and production startup uses the existing `bin/start` / LaunchAgent pattern.

## Data Model

Add app-side records:

- `AgentRun`: one continuous runner process or logical session.
- `AgentEvent`: every action, recommendation, error, heartbeat, and skipped action.
- `AgentRecommendation`: reviewable proposed action when direct mutation is not allowed or confidence is low.

Suggested fields:

- `agent_runs`: `user_id`, `status`, `pid`, `started_at`, `stopped_at`, `last_heartbeat_at`, `metadata`.
- `agent_events`: `user_id`, `agent_run_id`, `event_type`, `target_type`, `target_id`, `summary`, `payload`, `created_at`.
- `agent_recommendations`: `user_id`, `agent_event_id`, `target_type`, `target_id`, `action`, `risk_level`, `reasoning`, `payload`, `status`, `reviewed_at`.

Statuses should be Rails enums: `pending`, `approved`, `dismissed`, `applied`, `failed`.

## UI

Settings page:

- Enable local agent.
- Enable destructive actions.
- Show current status: disabled, starting, running, stale, stopped, failed.
- Show latest heartbeat and last action.
- Manual "Run now" button for a cycle.

Review page:

- List pending recommendations.
- Show target, action, reasoning, and payload.
- Approve applies through the same Rails domain service used by direct agent actions.
- Dismiss records the decision and keeps the audit trail.

The first implementation keeps the audit trail in the Local Agent settings area. Idea/detail pages are not changed until a later UI pass.

## Error Handling

- Tool calls return structured errors; the runner should record and continue.
- Repeated model, bridge, or validation failures create `AgentEvent` errors and trigger exponential backoff.
- Conflicts cause the runner to re-read the target before retrying.
- Dangerous requests made while destructive actions are disabled create recommendations instead of errors.
- If local inference is unavailable, status becomes failed or waiting, and Rails does not mark work as processed.

## Testing

Rails tests:

- User local agent settings default to disabled and persist only allowed keys.
- Settings page renders and updates agent settings.
- Domain tools reject mutation when the agent is disabled.
- Domain tools convert destructive actions into recommendations when destructive autonomy is disabled.
- Domain tools apply destructive actions when destructive autonomy is enabled.
- Idea mutations create normal version/history records.
- Recommendations can be approved or dismissed.
- Supervisor avoids duplicate active runs.

Agent runtime tests:

- Runtime resolves local inference settings.
- Daemon loop calls `list_work`, acts, records events, and sleeps on empty work.
- Destructive-action policy from Rails settings is reflected in the prompt and tool behavior.
- The `idea-foundry` toolset excludes broad generic tools by default.

Integration tests:

- A fake model/tool loop processes a pending submission into an approval recommendation when destructive autonomy is off.
- The same action applies directly when destructive autonomy is on.
- A weak idea receives a note or todo without requiring destructive autonomy.

## Rollout

1. Add Rails settings, models, and recommendation/audit services.
2. Add Rails domain tools and tests.
3. Rename and specialize the sibling agent runtime.
4. Add process supervision and heartbeat.
5. Add UI for settings, status, and recommendation review.
6. Wire startup scripts after the loop is stable.

## Open Decisions Resolved

- The agent covers all major app work surfaces from day one.
- The local agent does not use user-visible API tokens.
- Destructive autonomy is controlled by a separate setting.
- If destructive autonomy is off, the agent produces reviewable recommendations.
- Rails is the only component that mutates app data.
