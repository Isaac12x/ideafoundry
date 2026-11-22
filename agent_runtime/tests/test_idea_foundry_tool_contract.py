"""Guard: Python idea-foundry tool schemas must match the Rails Toolbox contract.

Rails' LocalAgent::Toolbox (idea-app) reads flat top-level args with specific
names. If these drift (e.g. nested "changes", "content" vs "body", "target_id"
vs "idea_id"), the model emits args Rails silently drops or rejects and the
end-to-end loop breaks without an error the model can see.
"""

from __future__ import annotations

from tools.idea_foundry_tools import SCHEMAS

# Required args Rails Toolbox fetches (raises without them) per tool.
RAILS_REQUIRED = {
    "get_settings": set(),
    "list_work": set(),
    "read_record": {"target_type", "target_id"},
    "update_idea": {"idea_id"},
    "create_note": {"idea_id", "body"},
    "create_todo": {"idea_id", "title"},
    "update_todo": {"todo_id"},
    "update_build_item": {"build_item_id"},
    "approve_submission": {"submission_id"},
    "reject_submission": {"submission_id"},
    "transition_idea": {"idea_id", "state"},
    "assign_list": {"idea_id", "list_id"},
    "assign_topology": {"idea_id", "topology_id"},
    "create_fact": {"body"},
    "create_maxim": {"body"},
    "run_enrichment": {"idea_id"},
    "create_recommendation": {"target_type", "target_id", "action"},
    "record_event": {"event_type"},
}

# Field names Rails never reads — their presence means the schema drifted.
FORBIDDEN_PROPERTIES = {"changes", "content", "statement", "expected_version"}


def test_schema_required_covers_rails_required():
    for tool, rails_required in RAILS_REQUIRED.items():
        props = set(SCHEMAS[tool]["parameters"]["properties"])
        required = set(SCHEMAS[tool]["parameters"].get("required", []))
        # Every field Rails fetches must be an allowed property and required.
        assert rails_required <= props, f"{tool}: missing props {rails_required - props}"
        assert rails_required <= required, f"{tool}: not required {rails_required - required}"


def test_no_drifted_property_names():
    for tool, schema in SCHEMAS.items():
        props = set(schema["parameters"]["properties"])
        leaked = props & FORBIDDEN_PROPERTIES
        assert not leaked, f"{tool}: drifted properties {leaked}"


def test_target_id_only_on_polymorphic_tools():
    # Mutating tools must key on idea_id, not target_id (the original drift bug).
    # Only polymorphic tools legitimately take target_type/target_id.
    allowed = {"read_record", "create_recommendation", "record_event"}
    for tool, schema in SCHEMAS.items():
        if "target_id" in schema["parameters"]["properties"]:
            assert tool in allowed, tool
