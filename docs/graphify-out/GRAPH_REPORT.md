# Graph Report - docs  (2026-07-21)

## Corpus Check
- 21 files · ~33,057 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 475 nodes · 454 edges · 37 communities
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5fc9615b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]

## God Nodes (most connected - your core abstractions)
1. `Local Idea Foundry Agent` - 18 edges
2. `Napkin Calculations Implementation Plan` - 16 edges
3. `Task 2: Add routes and controller action` - 14 edges
4. `Task 3: Views + Turbo Streams` - 11 edges
5. `Task 1: Update User model — integer contrast storage` - 11 edges
6. `Settings/Topologies Overhaul` - 10 edges
7. `Task 1: Migration + Model` - 10 edges
8. `Task 5: JS Graph Controller — Read Settings from JSON` - 10 edges
9. `Voice ID Inline Enrollment Implementation Plan` - 10 edges
10. `Task 3: Remove enrollment infrastructure` - 10 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities (37 total, 0 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (41): code:ruby (test "PATCH settings/security enabling voice id with valid s), code:ruby (def enroll_voice), code:ruby (def create_voice), code:ruby (def voice_id_samples), code:bash (rm app/views/typing_locks/enroll_voice.html.erb), code:ruby (redirect_for_typing_lock(enroll_voice_id_path(return_to: tar), code:ruby (redirect_for_typing_lock(settings_security_path)), code:bash (bin/rails routes | grep voice) (+33 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (36): code:ruby (test "GET settings/display renders display page" do), code:block12 (bin/rails test test/controllers/settings_controller_test.rb), code:ruby (get 'settings/display', to: 'settings#display', as: :setting), code:ruby (def display), code:ruby (redirect_to settings_path, notice: 'Display quote updated.'), code:ruby (redirect_to settings_display_path, notice: 'Display settings), code:ruby (render :index, status: :unprocessable_content), code:ruby (render :display, status: :unprocessable_content) (+28 more)

### Community 2 - "Community 2"
Cohesion: 0.06
Nodes (34): Build Next Backlog — Implementation Plan, code:ruby (# test/models/build_item_test.rb), code:ruby (# test/controllers/build_items_controller_test.rb), code:bash (bin/rails test test/controllers/build_items_controller_test.), code:ruby (# Build Next backlog), code:ruby (# app/controllers/build_items_controller.rb), code:bash (bin/rails test test/controllers/build_items_controller_test.), code:bash (git add -A && git commit -m "feat: add BuildItemsController ) (+26 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (31): code:ruby (test "topology_settings returns defaults when none stored" d), code:erb (<%= link_to settings_topologies_path, class: "settings-row" ), code:bash (git add app/views/settings/topologies.html.erb app/views/set), code:ruby (require "test_helper"), code:ruby (# before:), code:ruby (# before:), code:ruby (def graph_settings_for_response(topology_id = nil)), code:bash (git add app/controllers/topologies_controller.rb test/contro) (+23 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (30): code:ruby (# test/helpers/email_theme_helper_test.rb), code:ruby (def email), code:bash (git add app/controllers/settings_controller.rb test/controll), code:erb (<div style="margin-bottom: 1.5rem;">), code:bash (git add app/views/settings/email.html.erb), code:ruby (def share_idea(idea, recipient_email, sender_name: nil)), code:erb (<div style="max-width: 600px; margin: 0 auto; font-family: -), code:bash (git add app/mailers/idea_mailer.rb app/views/idea_mailer/sha) (+22 more)

### Community 5 - "Community 5"
Cohesion: 0.09
Nodes (21): Back-of-the-Napkin Calculations per Idea, code:ruby (add_column :ideas, :napkin_calculations, :json), code:json ({), Controller param handling, Data Model, Files, Form (create/edit), Formula Engine (+13 more)

### Community 6 - "Community 6"
Cohesion: 0.10
Nodes (19): 1. Data Model, 2. Background Job — `CheckAppUpgradeJob`, 3. Toast Notification, 4. Settings Upgrade Bar, 5. Upgrade Action, 6. Version Comparison Logic, 7. Files Touched / Created, App Upgrade Path — Design Spec (+11 more)

### Community 7 - "Community 7"
Cohesion: 0.10
Nodes (19): Architecture, Autonomy Policy, code:ruby ({), Continuous Loop, Current Context, Data Model, Error Handling, Goal (+11 more)

### Community 8 - "Community 8"
Cohesion: 0.11
Nodes (18): `application_controller.rb`, code:block1 (if voice_id enabled:), code:ruby (elsif @user.voice_id_requested? && !@user.voice_id_configure), Controller (`settings_controller.rb#update_security`), Design, Goal, JS / Stimulus, Model (`user.rb`) (+10 more)

### Community 9 - "Community 9"
Cohesion: 0.13
Nodes (14): code:bash (bin/rails test test/models/idea_work_link_test.rb test/contr), Current App Findings, Feature Slices, First PR Proposal: External Work Links + Export Coverage Prep, IP Continuity and Relatedness Implementation Plan, Open Product Decisions, Slice 1: External Work / Plan Links, Slice 2: IP Asset Registry and Registration Loop Closure (+6 more)

### Community 10 - "Community 10"
Cohesion: 0.14
Nodes (13): Calendar Reminder per Idea, code:block1 (BEGIN:VCALENDAR), code:block2 (https://calendar.google.com/calendar/render?action=TEMPLATE), Event Content, Files Changed, Google Calendar Link, .ics Generation (client-side), Implementation (+5 more)

### Community 11 - "Community 11"
Cohesion: 0.14
Nodes (13): Architecture, Attachment System Design, code:ruby (resources :attachments, only: [:create, :destroy, :update], ), code:html (<dialog data-controller="attachment-viewer" ...>), Controller: `IdeaAttachmentsController`, Data flow: Replace file, Goals, Key Invariants (+5 more)

### Community 12 - "Community 12"
Cohesion: 0.15
Nodes (12): code:ruby ("topology_settings" => {), code:json ({ "nodes": [...], "links": [...], "settings": { "dag_mode": ), Controller: Settings, Controller: Topologies, Decision, JS: topology_graph_controller, Model: User, Per-Topology Overrides (+4 more)

### Community 13 - "Community 13"
Cohesion: 0.15
Nodes (12): code:ruby (require "test_helper"), code:ruby (class CreateIdeaAgentTokens < ActiveRecord::Migration[8.0]), code:ruby (class IdeaAgentToken < ApplicationRecord), code:ruby (has_many :idea_agent_tokens, dependent: :destroy), code:ruby (require "test_helper"), code:ruby (require "test_helper"), code:bash (git add app db test config docs CHANGELOG.md), Idea Agent Document Access Implementation Plan (+4 more)

### Community 14 - "Community 14"
Cohesion: 0.18
Nodes (11): code:erb (<%# app/views/build_items/index.html.erb %>), code:erb (<%# app/views/build_items/_build_item.html.erb %>), code:erb (<%# app/views/build_items/_form.html.erb %>), code:erb (<%# app/views/build_items/_edit_form.html.erb %>), code:erb (<%# app/views/build_items/create.turbo_stream.erb %>), code:erb (<%# app/views/build_items/update.turbo_stream.erb %>), code:erb (<%# app/views/build_items/destroy.turbo_stream.erb %>), code:erb (<%# app/views/build_items/toggle.turbo_stream.erb %>) (+3 more)

### Community 15 - "Community 15"
Cohesion: 0.18
Nodes (11): code:ruby (test "display_contrast returns 100 by default" do), code:bash (git add app/models/user.rb test/controllers/settings_control), code:block2 (bin/rails test test/controllers/settings_controller_test.rb), code:ruby (ALLOWED_CONTRAST_VALUES = %w[normal high].freeze), code:ruby (def display_contrast), code:ruby (def display_contrast), code:ruby (if ALLOWED_CONTRAST_VALUES.include?(contrast) && contrast !=), code:ruby (contrast_int = contrast.to_i.clamp(70, 150)) (+3 more)

### Community 16 - "Community 16"
Cohesion: 0.18
Nodes (10): code:block1 (resources :ideas do resources :licensors, only: [:create] en), Data model, Goal, Idea show page, Licensing CRM + Idea Detail UI — Design, /licensing/crm (Twenty-style, app dark theme via existing CSS vars), Routes, Skipped (v1) (+2 more)

### Community 17 - "Community 17"
Cohesion: 0.20
Nodes (9): code:bash (docker compose build voice-id web), code:bash (docker compose up), code:bash (docker compose up voice-id), code:bash (VOICE_ID_SERVICE_URL=http://localhost:8000 bin/rails server), Configuration, Local Voice ID, Offline behavior, Running Rails outside Docker (+1 more)

### Community 18 - "Community 18"
Cohesion: 0.20
Nodes (10): code:javascript (this._settings = this._data.settings || {}), code:javascript (static values = {), code:javascript (// Apply persisted settings as initial values), code:javascript (.nodeVal(n => n.val || (n.type === 'idea' ? (this._settings.), code:javascript (// before:), code:javascript (// before:), code:javascript (.onNodeClick(node => {), code:javascript (// Auto-fit if no specific focus and setting enabled) (+2 more)

### Community 19 - "Community 19"
Cohesion: 0.20
Nodes (9): code:block1 (Page header: "Display" + back link → settings_path), Contrast Storage, CSS, Display Settings Page — Design Spec, Goal, Out of Scope, Route & Controller, Settings Index Changes (+1 more)

### Community 20 - "Community 20"
Cohesion: 0.22
Nodes (8): Architecture, Email Template Themes Design, Files Changed, Scope, Settings UI, Storage, Summary, Themes

### Community 21 - "Community 21"
Cohesion: 0.29
Nodes (6): Build Next Backlog — Design, Data Model, Interactions, Purpose, Styling, UI

### Community 22 - "Community 22"
Cohesion: 0.29
Nodes (6): code:block1 (db/migrate/<ts>_add_napkin_calculations_to_ideas.rb        N), code:ruby (gem "dentaku", "~> 3.5"), code:bash (git add Gemfile Gemfile.lock package.json yarn.lock), Napkin Calculations Implementation Plan, Self-Review Checklist (run before merging), Task 1: Add `dentaku` gem and `hyperformula` package

### Community 23 - "Community 23"
Cohesion: 0.29
Nodes (7): code:ruby (def napkin_calculations_within_limits), code:bash (git add app/models/idea.rb test/models/idea_napkin_test.rb), code:ruby (require "test_helper"), code:ruby (# JSON serialization), code:ruby (validate :napkin_calculations_within_limits), code:ruby (# Napkin calculations helpers), Task 3: Idea model — serialize, helpers, size validation (TDD)

### Community 24 - "Community 24"
Cohesion: 0.29
Nodes (7): code:ruby (def security), code:ruby (def security), code:ruby (def load_security_page_vars), code:ruby (def update_security), code:bash (grep -n "was_voice_id_configured\|enroll_voice_id_path" app/), code:bash (bin/rails test test/controllers/settings_controller_test.rb), Task 4: Extract `load_security_page_vars` and rewrite `update_security`

### Community 25 - "Community 25"
Cohesion: 0.40
Nodes (4): Backup Contract, File Storage, Restore Notes, Storage Location

### Community 26 - "Community 26"
Cohesion: 0.40
Nodes (5): code:javascript (async ensureParserLoaded() {), code:javascript (setCell(ref, cell) {), code:javascript (computeDisplay(ref, cell) {), code:bash (git add app/javascript/controllers/napkin_controller.js), Task 10: Lazy-load `hyperformula` and wire formula evaluation

### Community 27 - "Community 27"
Cohesion: 0.40
Nodes (5): code:javascript (cellMouseDown(e) {), code:javascript (applyFormat() {), code:javascript (this.element.addEventListener("keydown", (e) => {), code:bash (git add app/javascript/controllers/napkin_controller.js), Task 11: Range selection + format toolbar

### Community 28 - "Community 28"
Cohesion: 0.50
Nodes (4): code:ruby (require "test_helper"), code:ruby (def idea_params), code:bash (git add app/controllers/ideas_controller.rb test/controllers), Task 4: Controller — permit and parse JSON param (TDD)

### Community 29 - "Community 29"
Cohesion: 0.50
Nodes (4): code:erb (<%# Renders idea.napkin_calculations as a static evaluated g), code:erb (<% if @idea.napkin_present? %>), code:bash (git add app/views/ideas/_napkin_readonly.html.erb app/views/), Task 6: Show-page partial `_napkin_readonly`

### Community 30 - "Community 30"
Cohesion: 0.50
Nodes (4): code:javascript (import { Controller } from "@hotwired/stimulus"), code:javascript (import NapkinController from "./napkin_controller"), code:bash (git add app/javascript/controllers/napkin_controller.js app/), Task 8: Stimulus controller — initial render & toggle (no eval yet)

### Community 31 - "Community 31"
Cohesion: 0.50
Nodes (4): code:css (.napkin-panel { padding: 0; }), code:css (*= require napkin), code:bash (git add app/assets/stylesheets/napkin.css app/assets/stylesh), Task 13: CSS styling

### Community 32 - "Community 32"
Cohesion: 0.50
Nodes (4): code:ruby (require "test_helper"), code:ruby (module NapkinHelper), code:bash (git add app/helpers/napkin_helper.rb test/helpers/napkin_hel), Task 5: NapkinHelper — server-side eval + cell formatter (TDD)

### Community 33 - "Community 33"
Cohesion: 0.50
Nodes (4): code:erb (<%# Locals: idea, form %>), code:erb (<!-- Back-of-the-napkin Calculations -->), code:bash (git add app/views/ideas/_napkin.html.erb app/views/ideas/_fo), Task 7: Form partial `_napkin` skeleton (collapsed by default)

### Community 34 - "Community 34"
Cohesion: 0.67
Nodes (3): code:ruby (require "application_system_test_case"), code:bash (git add test/system/napkin_calculations_test.rb), Task 14: System test — full round-trip

### Community 35 - "Community 35"
Cohesion: 0.67
Nodes (3): code:javascript (addRow() {), code:bash (git add app/javascript/controllers/napkin_controller.js), Task 12: Add/remove rows and columns

### Community 36 - "Community 36"
Cohesion: 0.67
Nodes (3): code:ruby (class AddNapkinCalculationsToIdeas < ActiveRecord::Migration), code:bash (git add db/migrate/*napkin* db/schema.rb), Task 2: Migration — add `napkin_calculations` JSON column

## Knowledge Gaps
- **352 isolated node(s):** `Storage Location`, `Backup Contract`, `Restore Notes`, `Runtime architecture`, `code:bash (docker compose build voice-id web)` (+347 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Napkin Calculations Implementation Plan` connect `Community 22` to `Community 32`, `Community 33`, `Community 34`, `Community 35`, `Community 36`, `Community 23`, `Community 26`, `Community 27`, `Community 28`, `Community 29`, `Community 30`, `Community 31`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Why does `Voice ID Inline Enrollment Implementation Plan` connect `Community 0` to `Community 24`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Why does `Files` connect `Community 1` to `Community 15`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **What connects `Storage Location`, `Backup Contract`, `Restore Notes` to the rest of the system?**
  _352 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.047619047619047616 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05405405405405406 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._