# Settings/Topologies Overhaul

## Problem
`settings/topologies` shows a topology list (duplicate of `/topologies`), not actual settings. No way to configure graph visuals, behavior, topology defaults, or display prefs.

## Decision
- Storage: all in `User.settings` JSON (Approach A)
- Per-topology overrides keyed by topology ID in same JSON
- Remove topology list from settings page entirely

## Schema

```ruby
"topology_settings" => {
  # Graph visuals
  "default_dag_mode" => "td",       # "td" | ""
  "show_ideas" => true,
  "node_size_topology" => 6,
  "node_size_idea" => 3,
  "bloom_strength" => 0.8,
  "fog_density" => 0.015,
  # Graph behavior
  "auto_fit_on_load" => true,
  "click_behavior" => "navigate",   # "navigate" | "focus"
  # Topology defaults
  "default_color" => "#DAA520",
  "default_type" => "custom",
  "max_depth" => 5,
  # Display prefs
  "default_view" => "tree",         # "tree" | "graph"
  "sort_order" => "position"        # "position" | "name" | "ideas_count"
}

"topology_overrides" => {
  "<topology_id>" => { "dag_mode" => "", "show_ideas" => false }
}
```

## View: Settings/Topologies
4 config sections replacing the topology list:
1. **Graph Visuals** - DAG mode, show ideas, node sizes, bloom, fog
2. **Graph Behavior** - Auto-fit, click behavior
3. **Topology Defaults** - Default color, type, max depth, sort order
4. **Display Preferences** - Default view (tree/graph)

Single save button. Link to `/topologies` for management.

## Per-Topology Overrides
On topology show/edit page: expandable "Override Graph Settings" section. Each field has "Use default" checkbox. Only non-default values stored.

## Model: User
- `DEFAULT_TOPOLOGY_SETTINGS` constant
- `topology_settings` - merges defaults with stored
- `update_topology_settings(params)`
- `topology_overrides_for(topology_id)` - merged global + overrides
- `update_topology_overrides(topology_id, params)`

## Controller: Settings
- `topologies` action: loads settings (no topology list)
- `update_topologies` action: saves settings form

## Controller: Topologies
- `graph_data` and `neighborhood` include resolved settings in JSON:
```json
{ "nodes": [...], "links": [...], "settings": { "dag_mode": "td", ... } }
```

## JS: topology_graph_controller
Read settings from JSON response instead of hardcoded values. Apply bloom, fog, node sizes, DAG mode from resolved settings.
