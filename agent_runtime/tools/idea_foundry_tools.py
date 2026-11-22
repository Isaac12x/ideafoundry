"""Idea Foundry domain tools proxied to Rails."""

from __future__ import annotations

from typing import Any

from idea_foundry_agent.bridge import RailsToolBridge
from tools.registry import registry


IDEA_FOUNDRY_TOOL_NAMES = (
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
)


def _bridge_client() -> RailsToolBridge:
    return RailsToolBridge()


def _tool_handler(tool_name: str):
    def handler(args: dict[str, Any] | None, **_: Any) -> str:
        return _bridge_client().call_tool_json(tool_name, args or {})

    return handler


def _object_schema(description: str) -> dict[str, Any]:
    return {
        "type": "object",
        "description": description,
        "additionalProperties": True,
    }


_REASONING = {
    "type": "string",
    "description": "Short rationale; stored on the Rails audit event.",
}
_ID = {"type": ["string", "integer"]}
# Idea scores are 1-9 integers in Rails but accept strings for lenient models.
_SCORE = {"type": ["integer", "string", "null"]}


# Idea lifecycle states accepted by Rails Toolbox#transition_idea!.
IDEA_STATES = (
    "triage",
    "idea_new",
    "first_try",
    "second_try",
    "incubating",
    "validated",
    "parked",
    "rejected",
    "shipped",
)


# Field names mirror what LocalAgent::Toolbox reads in idea-app. Keep them in
# sync: Rails reads flat top-level keys (not nested "changes") and specific
# names (body, idea_id, commit_message, review_notes). See its toolbox_test.rb.
SCHEMAS: dict[str, dict[str, Any]] = {
    "get_settings": {
        "description": "Read current Rails local-agent settings and status.",
        "parameters": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    "list_work": {
        "description": "List prioritized Idea Foundry work candidates.",
        "parameters": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 50,
                    "description": "Maximum number of candidates to return.",
                },
            },
            "additionalProperties": False,
        },
    },
    "read_record": {
        "description": "Read fresh context for a record. Use the target_type/target_id from list_work.",
        "parameters": {
            "type": "object",
            "properties": {
                "target_type": {"type": "string"},
                "target_id": _ID,
            },
            "required": ["target_type", "target_id"],
            "additionalProperties": False,
        },
    },
    "update_idea": {
        "description": "Constructively update an idea's fields through Rails history hooks. Provide only the fields to change.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "title": {"type": "string"},
                "description": {"type": "string"},
                "trl": _SCORE,
                "difficulty": _SCORE,
                "opportunity": _SCORE,
                "timing": _SCORE,
                "difficulty_explanation": {"type": "string"},
                "opportunity_explanation": {"type": "string"},
                "timing_explanation": {"type": "string"},
                "metadata": _object_schema("Idea metadata to merge."),
                "commit_message": {
                    "type": "string",
                    "description": "History version message for this edit.",
                },
                "base_version_id": {
                    "type": ["string", "integer", "null"],
                    "description": "Latest known version id; rejected if stale.",
                },
                "reasoning": _REASONING,
            },
            "required": ["idea_id"],
            "additionalProperties": False,
        },
    },
    "create_note": {
        "description": "Create a note attached to an idea.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "body": {"type": "string"},
                "parent_note_id": {"type": ["string", "integer", "null"]},
                "reasoning": _REASONING,
            },
            "required": ["idea_id", "body"],
            "additionalProperties": False,
        },
    },
    "create_todo": {
        "description": "Create a todo item for an idea.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "title": {"type": "string"},
                "reasoning": _REASONING,
            },
            "required": ["idea_id", "title"],
            "additionalProperties": False,
        },
    },
    "update_todo": {
        "description": "Update a todo item's title or completion through Rails validation.",
        "parameters": {
            "type": "object",
            "properties": {
                "todo_id": _ID,
                "title": {"type": "string"},
                "completed": {"type": "boolean"},
                "reasoning": _REASONING,
            },
            "required": ["todo_id"],
            "additionalProperties": False,
        },
    },
    "update_build_item": {
        "description": "Update a build item through Rails validation.",
        "parameters": {
            "type": "object",
            "properties": {
                "build_item_id": _ID,
                "title": {"type": "string"},
                "description": {"type": "string"},
                "completed": {"type": "boolean"},
                "reasoning": _REASONING,
            },
            "required": ["build_item_id"],
            "additionalProperties": False,
        },
    },
    "approve_submission": {
        "description": "Approve a submission when Rails policy allows it. Optional fields override the created idea.",
        "parameters": {
            "type": "object",
            "properties": {
                "submission_id": _ID,
                "title": {"type": "string"},
                "trl": _SCORE,
                "difficulty": _SCORE,
                "opportunity": _SCORE,
                "timing": _SCORE,
                "list_id": {"type": ["string", "integer", "null"]},
                "topology_ids": {"type": "array", "items": _ID},
                "reasoning": _REASONING,
            },
            "required": ["submission_id"],
            "additionalProperties": False,
        },
    },
    "reject_submission": {
        "description": "Reject a submission, or create a recommendation if destructive actions are disabled.",
        "parameters": {
            "type": "object",
            "properties": {
                "submission_id": _ID,
                "review_notes": {
                    "type": "string",
                    "description": "Note stored on the submission when rejected.",
                },
                "reasoning": _REASONING,
            },
            "required": ["submission_id", "reasoning"],
            "additionalProperties": False,
        },
    },
    "transition_idea": {
        "description": "Transition an idea lifecycle state through Rails policy.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "state": {"type": "string", "enum": list(IDEA_STATES)},
                "cool_off_days": {
                    "type": ["integer", "null"],
                    "description": "Cool-off length when transitioning to incubating.",
                },
                "reasoning": _REASONING,
            },
            "required": ["idea_id", "state", "reasoning"],
            "additionalProperties": False,
        },
    },
    "assign_list": {
        "description": "Assign an idea to an Idea Foundry list.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "list_id": _ID,
                "reasoning": _REASONING,
            },
            "required": ["idea_id", "list_id"],
            "additionalProperties": False,
        },
    },
    "assign_topology": {
        "description": "Assign an idea to an Idea Foundry topology.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "topology_id": _ID,
                "reasoning": _REASONING,
            },
            "required": ["idea_id", "topology_id"],
            "additionalProperties": False,
        },
    },
    "create_fact": {
        "description": "Create a knowledge-base fact.",
        "parameters": {
            "type": "object",
            "properties": {
                "body": {"type": "string"},
                "reasoning": _REASONING,
            },
            "required": ["body"],
            "additionalProperties": False,
        },
    },
    "create_maxim": {
        "description": "Create a knowledge-base maxim.",
        "parameters": {
            "type": "object",
            "properties": {
                "body": {"type": "string"},
                "reasoning": _REASONING,
            },
            "required": ["body"],
            "additionalProperties": False,
        },
    },
    "run_enrichment": {
        "description": "Request Rails enrichment for an idea.",
        "parameters": {
            "type": "object",
            "properties": {
                "idea_id": _ID,
                "query": {"type": ["string", "null"]},
                "sources": {"type": "array", "items": {"type": "string"}},
                "reasoning": _REASONING,
            },
            "required": ["idea_id"],
            "additionalProperties": False,
        },
    },
    "create_recommendation": {
        "description": "Create a reviewable AgentRecommendation.",
        "parameters": {
            "type": "object",
            "properties": {
                "target_type": {"type": "string"},
                "target_id": {"type": ["string", "integer"]},
                "action": {"type": "string"},
                "risk_level": {
                    "type": "string",
                    "enum": ["low", "medium", "high"],
                },
                "reasoning": {"type": "string"},
                "payload": _object_schema("Proposed action payload."),
            },
            "required": [
                "target_type",
                "target_id",
                "action",
                "risk_level",
                "reasoning",
                "payload",
            ],
            "additionalProperties": False,
        },
    },
    "record_event": {
        "description": "Record an AgentEvent summary, heartbeat, skip, recommendation, error, or action.",
        "parameters": {
            "type": "object",
            "properties": {
                "event_type": {"type": "string"},
                "summary": {"type": "string"},
                "target_type": {"type": ["string", "null"]},
                "target_id": {"type": ["string", "integer", "null"]},
                "payload": _object_schema("Structured event payload."),
            },
            "required": ["event_type", "summary"],
            "additionalProperties": False,
        },
    },
}


registry.register(
    name="get_settings",
    toolset="idea-foundry",
    schema=SCHEMAS["get_settings"],
    handler=_tool_handler("get_settings"),
    description=SCHEMAS["get_settings"]["description"],
    emoji="IF",
)

for _tool_name in IDEA_FOUNDRY_TOOL_NAMES[1:]:
    registry.register(
        name=_tool_name,
        toolset="idea-foundry",
        schema=SCHEMAS[_tool_name],
        handler=_tool_handler(_tool_name),
        description=SCHEMAS[_tool_name]["description"],
        emoji="IF",
    )
