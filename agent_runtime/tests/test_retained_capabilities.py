from __future__ import annotations

from hermes_cli.config import DEFAULT_CONFIG
from model_tools import get_tool_definitions
from toolsets import resolve_toolset


def test_webapp_defaults_keep_skills_and_self_improvement_enabled():
    assert DEFAULT_CONFIG["toolsets"] == ["webapp-agent"]
    assert DEFAULT_CONFIG["skills"]["creation_nudge_interval"] == 1
    assert DEFAULT_CONFIG["curator"]["enabled"] is True


def test_compat_webapp_toolset_keeps_skills_memory_and_connectors():
    tools = set(resolve_toolset("webapp-agent"))

    assert {"skills_list", "skill_view", "skill_manage"} <= tools
    assert {"memory", "session_search"} <= tools
    assert {"send_message", "ha_call_service"} <= tools
    assert {"web_search", "browser_navigate", "execute_code"} <= tools


def test_idea_foundry_toolset_is_limited_to_rails_domain_tools():
    tools = set(resolve_toolset("idea-foundry"))

    assert {
        "get_settings",
        "list_work",
        "read_record",
        "update_idea",
        "create_note",
        "create_todo",
        "update_todo",
        "update_build_item",
        "approve_submission",
        "reject_submission",
        "transition_idea",
        "assign_list",
        "assign_topology",
        "create_fact",
        "create_maxim",
        "run_enrichment",
        "create_recommendation",
        "record_event",
    } == tools
    assert {"terminal", "read_file", "browser_navigate", "web_search"} & tools == set()


def test_idea_foundry_tool_schemas_are_registered():
    tool_names = {
        tool["function"]["name"]
        for tool in get_tool_definitions(["idea-foundry"], quiet_mode=True)
    }

    assert tool_names == set(resolve_toolset("idea-foundry"))
