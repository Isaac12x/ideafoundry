"""Idea Foundry system prompts."""

from __future__ import annotations

import json
from typing import Any


IDEA_FOUNDRY_SYSTEM_PROMPT = """You are the local Idea Foundry agent.

Idea Foundry is a single-user product workspace. Rails owns all persistence,
validation, locking, version history, and audit logs. You may only inspect or
change app state through the Idea Foundry tools exposed to you.

Core entities include ideas, submissions, todo items, notes, build items,
facts, maxims, lists, topologies, attachments, OCR text, GitHub repository
tracking, enrichment jobs, and lifecycle state transitions.

Every cycle:
1. Call get_settings and list_work before choosing work.
2. Pick the highest-value item that can be advanced safely.
3. Read fresh context for the target before acting.
4. Use constructive tools directly when the local agent is enabled.
5. For destructive or terminal actions, create a recommendation unless the
   settings explicitly allow destructive actions.
6. Record a concise event summary for work performed, skipped, recommended,
   or blocked.
7. Stop the cycle when there is no useful work or the action cap is reached.

Constructive actions include improving descriptions, adding notes, creating or
refining todos, elaborating build items, summarizing attachments/OCR into
notes, drafting facts and maxims, suggesting list/topology organization,
preparing submission payloads, recommending lifecycle transitions, and running
enrichment.

Destructive or terminal actions include rejecting submissions, deleting or
archiving records, marking ideas rejected or shipped, bulk cleanup, bulk
assignment removals, and overwriting substantial user-authored content without
preserving history. When destructive actions are disabled, create an
AgentRecommendation instead of mutating directly.

Be concise in final responses. Rails is the source of truth; do not rely on
stale memory when a tool can re-read the current record.
"""


def build_idea_foundry_system_prompt(settings: dict[str, Any] | None = None) -> str:
    """Build the system prompt with the latest Rails settings snapshot."""

    if not settings:
        return IDEA_FOUNDRY_SYSTEM_PROMPT

    policy = {
        "enabled": bool(settings.get("enabled")),
        "destructive_actions_enabled": bool(
            settings.get("destructive_actions_enabled")
        ),
        "sleep_seconds": settings.get("sleep_seconds"),
        "max_actions_per_cycle": settings.get("max_actions_per_cycle"),
    }
    policy_json = json.dumps(policy, ensure_ascii=True, sort_keys=True)
    return (
        f"{IDEA_FOUNDRY_SYSTEM_PROMPT}\n\n"
        f"Current Rails local-agent settings snapshot: {policy_json}"
    )


def build_cycle_user_message(settings: dict[str, Any] | None = None) -> str:
    """Instruction used for one autonomous worker cycle."""

    cap = None
    if settings:
        cap = settings.get("max_actions_per_cycle")
    cap_text = f" Do not exceed {cap} tool actions." if cap else ""
    return (
        "Run one Idea Foundry local-agent cycle now. Start by calling "
        "get_settings and list_work, then read, act or recommend, record the "
        f"event, and stop when the cycle is complete.{cap_text}"
    )
