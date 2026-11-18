# Settings/Topologies Overhaul — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the topology list on settings/topologies with actual configurable settings for graph visuals, behavior, topology defaults, and display prefs. Support per-topology overrides.

**Architecture:** All settings stored in `User.settings` JSON column (existing pattern). Global defaults in `topology_settings` key, per-topology overrides in `topology_overrides` key. Graph JSON endpoints include resolved settings so the JS controller reads them instead of hardcoded values.

**Tech Stack:** Rails 8, Minitest, Stimulus.js, 3d-force-graph/Three.js

---

### Task 1: User Model — Topology Settings Accessors

**Files:**
- Modify: `app/models/user.rb:36` (after existing constants)
- Test: `test/models/user_test.rb`

**Step 1: Write failing tests**

Add to `test/models/user_test.rb`:

```ruby
test "topology_settings returns defaults when none stored" do
  @user.save!
  expected = User::DEFAULT_TOPOLOGY_SETTINGS
  assert_equal expected, @user.topology_settings
end

test "topology_settings merges stored with defaults" do
  @user.settings = { 'topology_settings' => { 'show_ideas' => false } }
  @user.save!
  assert_equal false, @user.topology_settings['show_ideas']
  assert_equal 'td', @user.topology_settings['default_dag_mode']
end

test "update_topology_settings persists allowed keys" do
  @user.save!
  @user.update_topology_settings({ 'show_ideas' => false, 'bloom_strength' => 0.5 })
  @user.reload
  assert_equal false, @user.topology_settings['show_ideas']
  assert_equal 0.5, @user.topology_settings['bloom_strength']
end

test "update_topology_settings rejects unknown keys" do
  @user.save!
  @user.update_topology_settings({ 'show_ideas' => false, 'hacker' => 'bad' })
  @user.reload
  assert_nil @user.settings.dig('topology_settings', 'hacker')
end

test "topology_overrides_for returns global when no overrides" do
  @user.save!
  resolved = @user.topology_overrides_for(999)
  assert_equal 'td', resolved['default_dag_mode']
end

test "topology_overrides_for merges per-topology overrides" do
  @user.settings = {
    'topology_settings' => { 'show_ideas' => true },
    'topology_overrides' => { '42' => { 'show_ideas' => false } }
  }
  @user.save!
  assert_equal false, @user.topology_overrides_for(42)['show_ideas']
  assert_equal true, @user.topology_overrides_for(99)['show_ideas']
end

test "update_topology_overrides stores per-topology settings" do
  @user.save!
  @user.update_topology_overrides(42, { 'show_ideas' => false, 'dag_mode' => '' })
  @user.reload
  overrides = @user.settings.dig('topology_overrides', '42')
  assert_equal false, overrides['show_ideas']
  assert_equal '', overrides['dag_mode']
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: 7 failures (methods/constants don't exist yet)

**Step 3: Implement model methods**

Add to `app/models/user.rb` after `DEFAULT_NOTIFICATION_CONTENT` (line 46):

```ruby
DEFAULT_TOPOLOGY_SETTINGS = {
  'default_dag_mode' => 'td',
  'show_ideas' => true,
  'node_size_topology' => 6,
  'node_size_idea' => 3,
  'bloom_strength' => 0.8,
  'fog_density' => 0.015,
  'auto_fit_on_load' => true,
  'click_behavior' => 'navigate',
  'default_color' => '#DAA520',
  'default_type' => 'custom',
  'max_depth' => 5,
  'default_view' => 'tree',
  'sort_order' => 'position'
}.freeze

ALLOWED_TOPOLOGY_SETTING_KEYS = DEFAULT_TOPOLOGY_SETTINGS.keys.freeze

ALLOWED_TOPOLOGY_OVERRIDE_KEYS = %w[
  dag_mode show_ideas node_size_topology node_size_idea
  bloom_strength fog_density auto_fit_on_load click_behavior
].freeze
```

Add methods after `update_notification_content` (after line 113):

```ruby
def topology_settings
  DEFAULT_TOPOLOGY_SETTINGS.merge(settings&.dig('topology_settings') || {})
end

def update_topology_settings(params)
  self.settings ||= {}
  self.settings['topology_settings'] = params.to_h.slice(*ALLOWED_TOPOLOGY_SETTING_KEYS)
  save
end

def topology_overrides_for(topology_id)
  overrides = settings&.dig('topology_overrides', topology_id.to_s) || {}
  topology_settings.merge(overrides)
end

def update_topology_overrides(topology_id, params)
  self.settings ||= {}
  self.settings['topology_overrides'] ||= {}
  filtered = params.to_h.slice(*ALLOWED_TOPOLOGY_OVERRIDE_KEYS)
  if filtered.empty?
    self.settings['topology_overrides'].delete(topology_id.to_s)
  else
    self.settings['topology_overrides'][topology_id.to_s] = filtered
  end
  save
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: All pass

**Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "feat: add topology settings accessors to User model"
```

---

### Task 2: Settings Controller — Topology Settings Actions

**Files:**
- Modify: `app/controllers/settings_controller.rb:86-88`
- Modify: `config/routes.rb:76`
- Test: `test/controllers/settings_controller_test.rb` (create)

**Step 1: Write failing controller test**

Create `test/controllers/settings_controller_test.rb`:

```ruby
require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: 'test@example.com', name: 'Test')
  end

  test "GET settings/topologies renders settings page" do
    get settings_topologies_path
    assert_response :success
    assert_select "h2", "Topology & Graph Settings"
  end

  test "PATCH settings/topologies updates topology settings" do
    patch settings_topologies_path, params: {
      topology_settings: {
        show_ideas: "false",
        bloom_strength: "0.5",
        default_view: "graph"
      }
    }
    assert_redirected_to settings_topologies_path
    @user.reload
    assert_equal false, @user.topology_settings['show_ideas']
    assert_equal 0.5, @user.topology_settings['bloom_strength']
    assert_equal 'graph', @user.topology_settings['default_view']
  end

  test "PATCH settings/topologies rejects invalid keys" do
    patch settings_topologies_path, params: {
      topology_settings: { hacker: "bad", show_ideas: "true" }
    }
    assert_redirected_to settings_topologies_path
    @user.reload
    assert_nil @user.settings&.dig('topology_settings', 'hacker')
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/settings_controller_test.rb -v`
Expected: Failures (no PATCH route, no update action, wrong page content)

**Step 3: Add route**

In `config/routes.rb`, replace line 76:

```ruby
# before:
get 'settings/topologies', to: 'settings#topologies'

# after:
get 'settings/topologies', to: 'settings#topologies'
patch 'settings/topologies', to: 'settings#update_topologies'
```

**Step 4: Update controller actions**

In `app/controllers/settings_controller.rb`, replace the `topologies` method (line 86-88):

```ruby
def topologies
  @topology_settings = @user.topology_settings
end

def update_topologies
  raw = params.require(:topology_settings).permit(*User::ALLOWED_TOPOLOGY_SETTING_KEYS)
  # Cast booleans and numerics
  coerced = raw.to_h.each_with_object({}) do |(k, v), h|
    default = User::DEFAULT_TOPOLOGY_SETTINGS[k]
    h[k] = case default
            when true, false then ActiveModel::Type::Boolean.new.cast(v)
            when Integer then v.to_i
            when Float then v.to_f
            else v.to_s
            end
  end

  if @user.update_topology_settings(coerced)
    redirect_to settings_topologies_path, notice: 'Topology & graph settings updated.'
  else
    @topology_settings = @user.topology_settings
    flash.now[:alert] = 'Failed to update settings.'
    render :topologies, status: :unprocessable_entity
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/settings_controller_test.rb -v`
Expected: GET test may still fail (view not updated yet). PATCH tests should pass.

**Step 6: Commit**

```bash
git add app/controllers/settings_controller.rb config/routes.rb test/controllers/settings_controller_test.rb
git commit -m "feat: add topology settings update action and route"
```

---

### Task 3: Settings/Topologies View — Replace List with Settings Form

**Files:**
- Modify: `app/views/settings/topologies.html.erb` (full rewrite)
- Modify: `app/views/settings/index.html.erb:19-25` (update description)

**Step 1: Rewrite the settings/topologies view**

Replace entire contents of `app/views/settings/topologies.html.erb`:

```erb
<div class="settings-container">
  <div class="page-header">
    <h2>Topology & Graph Settings</h2>
    <div class="header-actions">
      <%= link_to settings_path, class: "btn btn-sm" do %>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
        Back to Settings
      <% end %>
      <%= link_to topologies_path, class: "btn btn-sm" do %>
        Manage Topologies
      <% end %>
    </div>
  </div>

  <%= form_with url: settings_topologies_path, method: :patch, local: true do |form| %>

    <!-- Graph Visuals -->
    <div class="config-section">
      <h3>Graph Visuals</h3>
      <p class="config-description">Default visual settings for the 3D topology graph.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label">
            Layout Mode
            <span class="weight-description">Default graph layout when opened</span>
          </label>
          <%= form.select "topology_settings[default_dag_mode]",
              options_for_select([["Tree (top-down)", "td"], ["Force-directed (free)", ""]], @topology_settings['default_dag_mode']),
              {}, class: "form-control" %>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Show Ideas
            <span class="weight-description">Display idea nodes in the graph by default</span>
          </label>
          <%= form.select "topology_settings[show_ideas]",
              options_for_select([["Yes", "true"], ["No", "false"]], @topology_settings['show_ideas'].to_s),
              {}, class: "form-control" %>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Topology Node Size
            <span class="weight-description">Base size of topology nodes (1-15)</span>
          </label>
          <div class="weight-input-group">
            <%= form.number_field "topology_settings[node_size_topology]",
                value: @topology_settings['node_size_topology'],
                min: 1, max: 15, step: 1, class: "weight-input" %>
          </div>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Idea Node Size
            <span class="weight-description">Base size of idea nodes (1-10)</span>
          </label>
          <div class="weight-input-group">
            <%= form.number_field "topology_settings[node_size_idea]",
                value: @topology_settings['node_size_idea'],
                min: 1, max: 10, step: 1, class: "weight-input" %>
          </div>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Bloom Strength
            <span class="weight-description">Glow intensity (0 = off, 2 = max)</span>
          </label>
          <div class="weight-input-group">
            <%= form.number_field "topology_settings[bloom_strength]",
                value: @topology_settings['bloom_strength'],
                min: 0, max: 2, step: 0.1, class: "weight-input" %>
          </div>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Fog Density
            <span class="weight-description">Atmospheric fog (0 = clear, 0.05 = dense)</span>
          </label>
          <div class="weight-input-group">
            <%= form.number_field "topology_settings[fog_density]",
                value: @topology_settings['fog_density'],
                min: 0, max: 0.05, step: 0.001, class: "weight-input" %>
          </div>
        </div>
      </div>
    </div>

    <!-- Graph Behavior -->
    <div class="config-section">
      <h3>Graph Behavior</h3>
      <p class="config-description">How the graph responds to interactions.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label">
            Auto-Fit on Load
            <span class="weight-description">Zoom to fit all nodes when graph loads</span>
          </label>
          <%= form.select "topology_settings[auto_fit_on_load]",
              options_for_select([["Yes", "true"], ["No", "false"]], @topology_settings['auto_fit_on_load'].to_s),
              {}, class: "form-control" %>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Click Behavior
            <span class="weight-description">What happens when you click a node</span>
          </label>
          <%= form.select "topology_settings[click_behavior]",
              options_for_select([["Navigate to page", "navigate"], ["Focus camera", "focus"]], @topology_settings['click_behavior']),
              {}, class: "form-control" %>
        </div>
      </div>
    </div>

    <!-- Topology Defaults -->
    <div class="config-section">
      <h3>Topology Defaults</h3>
      <p class="config-description">Defaults applied when creating new topologies.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label">
            Default Color
            <span class="weight-description">Color for new topologies</span>
          </label>
          <%= form.color_field "topology_settings[default_color]",
              value: @topology_settings['default_color'],
              class: "form-control", style: "width: 60px;" %>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Default Type
            <span class="weight-description">Type assigned to new topologies</span>
          </label>
          <%= form.select "topology_settings[default_type]",
              options_for_select([["Custom", "custom"], ["Predefined", "predefined"]], @topology_settings['default_type']),
              {}, class: "form-control" %>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Max Depth
            <span class="weight-description">Maximum nesting depth for hierarchies</span>
          </label>
          <div class="weight-input-group">
            <%= form.number_field "topology_settings[max_depth]",
                value: @topology_settings['max_depth'],
                min: 1, max: 20, step: 1, class: "weight-input" %>
          </div>
        </div>

        <div class="weight-item">
          <label class="weight-label">
            Sort Order
            <span class="weight-description">Default sort for topology lists</span>
          </label>
          <%= form.select "topology_settings[sort_order]",
              options_for_select([["Position (manual)", "position"], ["Name (A-Z)", "name"], ["Ideas count", "ideas_count"]], @topology_settings['sort_order']),
              {}, class: "form-control" %>
        </div>
      </div>
    </div>

    <!-- Display Preferences -->
    <div class="config-section">
      <h3>Display Preferences</h3>
      <p class="config-description">How topologies are displayed by default.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label">
            Default View
            <span class="weight-description">Initial view when opening the topologies page</span>
          </label>
          <%= form.select "topology_settings[default_view]",
              options_for_select([["Tree view", "tree"], ["Graph view", "graph"]], @topology_settings['default_view']),
              {}, class: "form-control" %>
        </div>
      </div>
    </div>

    <div class="config-actions">
      <%= form.submit "Save Settings", class: "btn btn-primary" %>
      <%= link_to "Reset to Defaults", settings_topologies_path,
          method: :patch,
          params: { topology_settings: User::DEFAULT_TOPOLOGY_SETTINGS },
          class: "btn btn-secondary",
          data: { turbo_confirm: "Reset all topology settings to defaults?" } %>
    </div>
  <% end %>
</div>
```

**Step 2: Update settings index description**

In `app/views/settings/index.html.erb`, change lines 19-25 (the topologies row description):

```erb
<%= link_to settings_topologies_path, class: "settings-row" do %>
  <div class="settings-row-info">
    <h3>Topologies & Graph</h3>
    <p>Configure graph visuals, behavior, and topology defaults</p>
  </div>
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>
<% end %>
```

**Step 3: Run tests**

Run: `bin/rails test test/controllers/settings_controller_test.rb -v`
Expected: All 3 tests pass

**Step 4: Commit**

```bash
git add app/views/settings/topologies.html.erb app/views/settings/index.html.erb
git commit -m "feat: replace topology list with settings form on settings/topologies"
```

---

### Task 4: Topologies Controller — Include Settings in Graph JSON

**Files:**
- Modify: `app/controllers/topologies_controller.rb:63-98` and `:100-145`
- Test: `test/controllers/topologies_controller_test.rb` (create)

**Step 1: Write failing tests**

Create `test/controllers/topologies_controller_test.rb`:

```ruby
require "test_helper"

class TopologiesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: 'test@example.com', name: 'Test')
    @topology = @user.topologies.create!(name: 'Test Topo', topology_type: :custom, color: '#ff0000')
  end

  test "graph_data includes settings in JSON" do
    get graph_data_topologies_path(format: :json)
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?('settings'), "Response should include settings"
    assert_equal 'td', json['settings']['default_dag_mode']
    assert_equal true, json['settings']['show_ideas']
  end

  test "graph_data includes custom settings" do
    @user.update_topology_settings({ 'show_ideas' => false, 'bloom_strength' => 0.3 })
    get graph_data_topologies_path(format: :json)
    json = JSON.parse(response.body)
    assert_equal false, json['settings']['show_ideas']
    assert_equal 0.3, json['settings']['bloom_strength']
  end

  test "neighborhood includes settings with per-topology overrides" do
    @user.update_topology_overrides(@topology.id, { 'show_ideas' => false, 'dag_mode' => '' })
    get neighborhood_topology_path(@topology, format: :json)
    json = JSON.parse(response.body)
    assert json.key?('settings')
    assert_equal false, json['settings']['show_ideas']
  end

  teardown do
    @topology&.destroy
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/topologies_controller_test.rb -v`
Expected: Failures (no 'settings' key in JSON)

**Step 3: Update graph_data action**

In `app/controllers/topologies_controller.rb`, replace line 97:

```ruby
# before:
render json: { nodes: nodes, links: links }

# after:
render json: { nodes: nodes, links: links, settings: graph_settings_for_response }
```

**Step 4: Update neighborhood action**

In `app/controllers/topologies_controller.rb`, replace line 144:

```ruby
# before:
render json: { nodes: nodes, links: links }

# after:
render json: { nodes: nodes, links: links, settings: graph_settings_for_response(@topology.id) }
```

**Step 5: Add private helper**

Add to private section of `app/controllers/topologies_controller.rb`:

```ruby
def graph_settings_for_response(topology_id = nil)
  if topology_id
    @user.topology_overrides_for(topology_id)
  else
    @user.topology_settings
  end
end
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/topologies_controller_test.rb -v`
Expected: All pass

**Step 7: Commit**

```bash
git add app/controllers/topologies_controller.rb test/controllers/topologies_controller_test.rb
git commit -m "feat: include resolved settings in graph JSON endpoints"
```

---

### Task 5: JS Graph Controller — Read Settings from JSON

**Files:**
- Modify: `app/javascript/controllers/topology_graph_controller.js`

**Step 1: Store settings from JSON response**

In `topology_graph_controller.js`, in `connect()` method (after line 33 `this._data = await res.json()`), add:

```javascript
this._settings = this._data.settings || {}
```

**Step 2: Apply settings to initial graph state**

Replace the static values block (lines 6-10) with:

```javascript
static values = {
  url: String,
  focusId: { type: String, default: "" },
  showIdeas: { type: Boolean, default: true },
  dagMode: { type: String, default: "" }
}
```

After `this._settings = this._data.settings || {}`, add:

```javascript
// Apply persisted settings as initial values
if (this._settings.show_ideas !== undefined) this.showIdeasValue = this._settings.show_ideas
if (this._settings.default_dag_mode !== undefined) this.dagModeValue = this._settings.default_dag_mode
```

**Step 3: Use settings in _initGraph**

In `_initGraph()`, replace the hardcoded `.nodeVal(n => n.val || 3)` (line 107) with:

```javascript
.nodeVal(n => n.val || (n.type === 'idea' ? (this._settings.node_size_idea || 3) : (this._settings.node_size_topology || 6)))
```

**Step 4: Use settings in _setupScene**

In `_setupScene(THREE)`, replace the fog line (line 183):

```javascript
// before:
scene.fog = new THREE.FogExp2(0x0c0c0f, 0.0018)

// after:
const fogDensity = this._settings.fog_density !== undefined ? this._settings.fog_density : 0.0018
scene.fog = new THREE.FogExp2(0x0c0c0f, fogDensity)
```

**Step 5: Use settings in _tryAddBloom**

In `_tryAddBloom(THREE)`, replace the bloom pass creation (lines 218-222):

```javascript
// before:
const bloomPass = new UnrealBloomPass(
  new THREE.Vector2(el.clientWidth, el.clientHeight),
  0.8,   // strength
  0.4,   // radius
  0.85   // threshold
)

// after:
const bloomStrength = this._settings.bloom_strength !== undefined ? this._settings.bloom_strength : 0.8
const bloomPass = new UnrealBloomPass(
  new THREE.Vector2(el.clientWidth, el.clientHeight),
  bloomStrength,
  0.4,
  0.85
)
```

**Step 6: Use settings in onNodeClick**

In `_initGraph()`, replace the onNodeClick handler (lines 121-127):

```javascript
.onNodeClick(node => {
  const behavior = this._settings.click_behavior || 'navigate'
  if (behavior === 'focus') {
    if (!node) return
    const distance = 120
    const distRatio = 1 + distance / Math.hypot(node.x, node.y, node.z)
    this._graph.cameraPosition(
      { x: node.x * distRatio, y: node.y * distRatio, z: node.z * distRatio },
      node, 1000
    )
  } else {
    if (node.url && window.Turbo) {
      window.Turbo.visit(node.url)
    } else if (node.url) {
      window.location.href = node.url
    }
  }
})
```

**Step 7: Auto-fit on load**

In `_initGraph()`, after the focus-node block (after line 155), add:

```javascript
// Auto-fit if no specific focus and setting enabled
if (!this.focusIdValue && this._settings.auto_fit_on_load !== false) {
  this._graph.onEngineStop(() => {
    this._graph.zoomToFit(600, 40)
    this._graph.onEngineStop(() => {})
  })
}
```

**Step 8: Manual test**

1. Visit `/settings/topologies`, change bloom to 0.2, save
2. Visit `/topologies`, switch to graph tab
3. Verify reduced bloom glow
4. Change click behavior to "focus", save
5. Visit graph, click node — should focus camera instead of navigating

**Step 9: Commit**

```bash
git add app/javascript/controllers/topology_graph_controller.js
git commit -m "feat: graph controller reads settings from JSON instead of hardcoded values"
```

---

### Task 6: Topologies Index — Respect Default View Setting

**Files:**
- Modify: `app/views/topologies/index.html.erb:1`
- Modify: `app/controllers/topologies_controller.rb:6`

**Step 1: Pass default view from controller**

In `app/controllers/topologies_controller.rb`, update the `index` action:

```ruby
def index
  @topologies = @user.topologies.roots.ordered.includes(:children)
  @default_view = @user.topology_settings['default_view'] || 'tree'
end
```

**Step 2: Use default view in template**

In `app/views/topologies/index.html.erb`, replace line 1:

```erb
<!-- before: -->
<div class="topologies-container" data-controller="tabs" data-tabs-default-tab-value="tree">

<!-- after: -->
<div class="topologies-container" data-controller="tabs" data-tabs-default-tab-value="<%= @default_view %>">
```

**Step 3: Manual test**

1. Set default view to "graph" in settings
2. Visit `/topologies`
3. Graph tab should be active by default

**Step 4: Commit**

```bash
git add app/views/topologies/index.html.erb app/controllers/topologies_controller.rb
git commit -m "feat: topologies index respects default view setting"
```

---

### Task 7: Per-Topology Override UI on Edit Page

**Files:**
- Modify: `app/views/topologies/_form.html.erb` (add override section)
- Modify: `app/controllers/topologies_controller.rb:40-53` (handle override params)

**Step 1: Add override fields to form partial**

In `app/views/topologies/_form.html.erb`, before the `form-actions` div (before line 62), add:

```erb
<% unless topology.new_record? %>
  <div class="form-panel" style="margin-top: 1rem;">
    <details>
      <summary style="cursor: pointer; font-weight: 600; padding: 0.5rem 0;">
        Override Graph Settings
        <small style="font-weight: 400; color: var(--text-muted);">— customize graph for this topology</small>
      </summary>
      <div style="margin-top: 1rem;">
        <% overrides = @user.settings&.dig('topology_overrides', topology.id.to_s) || {} %>

        <div class="form-group">
          <%= form.label "topology_overrides[dag_mode]", "Layout Mode" %>
          <%= form.select "topology_overrides[dag_mode]",
              options_for_select([["Use default", ""], ["Tree", "td"], ["Force-directed", "free"]], overrides['dag_mode'] || ""),
              {}, class: "form-control" %>
        </div>

        <div class="form-group">
          <%= form.label "topology_overrides[show_ideas]", "Show Ideas" %>
          <%= form.select "topology_overrides[show_ideas]",
              options_for_select([["Use default", ""], ["Yes", "true"], ["No", "false"]], overrides.key?('show_ideas') ? overrides['show_ideas'].to_s : ""),
              {}, class: "form-control" %>
        </div>

        <div class="form-group">
          <%= form.label "topology_overrides[bloom_strength]", "Bloom Strength" %>
          <%= form.number_field "topology_overrides[bloom_strength]",
              value: overrides['bloom_strength'] || "",
              min: 0, max: 2, step: 0.1, class: "form-control",
              placeholder: "Leave blank for default" %>
        </div>

        <div class="form-group">
          <%= form.label "topology_overrides[fog_density]", "Fog Density" %>
          <%= form.number_field "topology_overrides[fog_density]",
              value: overrides['fog_density'] || "",
              min: 0, max: 0.05, step: 0.001, class: "form-control",
              placeholder: "Leave blank for default" %>
        </div>
      </div>
    </details>
  </div>
<% end %>
```

**Step 2: Handle overrides in update action**

In `app/controllers/topologies_controller.rb`, update the `update` action:

```ruby
def update
  if @topology.update(topology_params)
    # Save per-topology graph overrides if provided
    if params[:topology_overrides].present?
      overrides = params[:topology_overrides].permit(*User::ALLOWED_TOPOLOGY_OVERRIDE_KEYS).to_h
      # Remove blank values (means "use default")
      overrides.reject! { |_, v| v.blank? }
      # Cast types
      overrides.transform_values! do |v|
        case v
        when 'true' then true
        when 'false' then false
        else v.match?(/\A-?\d+\.?\d*\z/) ? v.to_f : v
        end
      end
      @user.update_topology_overrides(@topology.id, overrides)
    end

    respond_to do |format|
      format.html { redirect_to topologies_path, notice: 'Topology updated.' }
      format.json { render json: @topology }
    end
  else
    @parent_options = @user.topologies.where.not(id: [@topology.id] + @topology.descendants.map(&:id)).ordered
    respond_to do |format|
      format.html { render :edit, status: :unprocessable_entity }
      format.json { render json: { errors: @topology.errors }, status: :unprocessable_entity }
    end
  end
end
```

**Step 3: Ensure @user available in edit view**

The `set_user` before_action already runs. No change needed.

**Step 4: Manual test**

1. Edit a topology, expand "Override Graph Settings"
2. Set show ideas to "No", save
3. Visit that topology's show page
4. Neighborhood graph should hide idea nodes

**Step 5: Commit**

```bash
git add app/views/topologies/_form.html.erb app/controllers/topologies_controller.rb
git commit -m "feat: add per-topology graph setting overrides on edit page"
```

---

### Task 8: Final Verification

**Step 1: Run all tests**

Run: `bin/rails test -v`
Expected: All pass

**Step 2: Manual smoke test**

1. `/settings` — verify "Topologies & Graph" label/description
2. `/settings/topologies` — verify 4 settings sections, no topology list
3. Change settings, save, verify persisted
4. Reset to defaults, verify
5. `/topologies` — verify default view respected
6. Graph tab — verify settings applied (bloom, fog, DAG mode)
7. Edit topology — override settings, verify on show page graph
8. `/topologies/graph_data.json` — verify `settings` key present

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete settings/topologies overhaul — settings form, graph integration, per-topology overrides"
```
