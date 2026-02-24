# Development

## Architecture Overview

### Backend

Standard Rails 8.0 MVC app. Key models:

- **Idea** — Core entity. Has lifecycle states (enum), scoring dimensions (trl/difficulty/opportunity/timing), computed score, version history, rich text description, file attachments, and metadata JSON.
- **Topology** — Hierarchical category tree (self-referential `parent_id`). Ideas can belong to multiple topologies. Changes broadcast via ActionCable.
- **Version** — Git-like snapshots. Each save creates a JSON snapshot with parent pointer forming a DAG. Supports diff and restore.
- **List** — Kanban boards. Ideas assigned to lists via `IdeaList` join table with position ordering.
- **Template** — Defines custom field definitions, section order, and tab layouts as JSON.
- **BuildItem** — Simple task/backlog items with position and completion state.

### Frontend

**Dual JavaScript pipeline:**

1. **Importmap** — Handles Stimulus controllers, Turbo, and standard JS. No build step required.
2. **esbuild** — Bundles only the 3D graph (`app/javascript/graph/`) because Three.js is too large for importmap. Output goes to `app/assets/builds/graph/`.

**Stimulus controllers** in `app/javascript/controllers/`:
- `topology_graph_controller` — Mounts the 3D force-directed graph
- `editor_controller` — TipTap rich text editor integration
- `drag_controller` — Kanban drag-and-drop
- `score_controller` — Real-time score calculation UI
- Plus ~11 more for various interactions

**TipTap** is loaded via ESM from `esm.sh` CDN (not bundled).

### Real-time

ActionCable powers live updates for the topology graph. `TopologyGraphChannel` broadcasts node/edge changes. The graph's `cable.js` subscribes and updates the 3D scene without page reload.

### Email Pipeline

```
Inbound email → Resend webhook → Action Mailbox → IdeasMailbox
  → Fuzzy-match subject to existing ideas
  → If match: append content + attachments
  → If ambiguous: store as pending_email in metadata for manual approval
  → If no match: create new idea
  → Compute SHA3 integrity hash
```

## Project Structure

```
app/
├── controllers/        # Rails controllers
├── models/             # ActiveRecord models + concerns
├── views/              # ERB templates
├── jobs/               # Solid Queue background jobs
├── mailboxes/          # Action Mailbox processors
├── mailers/            # Email templates
├── channels/           # ActionCable channels
└── javascript/
    ├── controllers/    # Stimulus controllers (importmap)
    └── graph/          # 3D graph bundle (esbuild)
config/
├── routes.rb           # All routes
├── recurring.yml       # Scheduled job definitions
├── database.yml        # SQLite config (4 databases)
└── importmap.rb        # JS importmap pins
db/
├── schema.rb           # Current schema
├── migrate/            # Migrations
├── seeds.rb            # Sample data
└── queue_migrate/      # Solid Queue migrations
storage/                # SQLite DBs + Active Storage files
```

## Common Tasks

### Running the Dev Server

```bash
bin/dev                          # Rails + esbuild watcher
# Or separately:
bin/rails server -p 3000         # Rails only
yarn build:watch                 # esbuild graph watcher only
```

### Running Tests

```bash
bin/rails test                   # All unit/integration tests
bin/rails test:system            # System tests (requires Chrome/Selenium)
bin/rails test test/models/      # Just model tests
bin/rails test test/models/idea_test.rb:42  # Specific test by line
```

### Database

```bash
bin/rails db:migrate             # Run pending migrations
bin/rails db:rollback            # Undo last migration
bin/rails db:seed                # Load sample data
bin/rails db:reset               # Drop, create, migrate, seed
bin/rails console                # Interactive Rails console
```

### Building the Graph Bundle

```bash
yarn build                       # One-shot production build (minified)
yarn build:watch                 # Watch mode for development
```

Output: `app/assets/builds/graph/index.js`

### Working with Credentials

```bash
EDITOR="code --wait" bin/rails credentials:edit
bin/rails credentials:show
```

## Idea Lifecycle States

```
idea_new (0) → triage (1) → first_try (2) ──→ validated (5) → shipped (8)
                  ↑              │
                  │         fail_attempt!
                  │              ↓
                  ├─── incubating (4) [cool-off timer]
                  │              │
                  │         cool-off expires
                  │              ↓
                  └──── second_try (3) ──→ validated (5)
                                 │
                            fail_attempt!
                                 ↓
                           incubating (4) → triage (1)

Any state → parked (6)
Any state → rejected (7) (except shipped)
```

State transitions are enforced in `Idea` model methods (`transition_to_first_try!`, `fail_attempt!`, `complete_attempt!`, `ship!`, etc.).

## Scoring System

Each idea has four dimensions scored 0-10:
- **TRL** (Technology Readiness Level)
- **Difficulty** (inverted — lower is harder)
- **Opportunity** (market size/potential)
- **Timing** (market timing relevance)

Composite score = weighted sum. Weights are user-configurable via Settings > Scoring.

## Adding a New Feature

1. **Model** — Add migrations, model logic, validations
2. **Controller** — CRUD actions, strong params
3. **Views** — ERB templates with Turbo Frames/Streams where appropriate
4. **Stimulus** — Add controller in `app/javascript/controllers/` (auto-registered via importmap)
5. **Routes** — Update `config/routes.rb`
6. **Tests** — Add tests in corresponding `test/` subdirectory

### Adding a Stimulus Controller

Create `app/javascript/controllers/my_feature_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    // ...
  }
}
```

It's auto-registered via importmap — no manual wiring needed.

### Adding a Background Job

Create `app/jobs/my_job.rb`:

```ruby
class MyJob < ApplicationJob
  queue_as :default

  def perform(args)
    # ...
  end
end
```

For recurring jobs, add to `config/recurring.yml`.

## Key Design Decisions

- **No authentication** — Single-user app. `ApplicationController#set_user` returns `User.first`. Secure at the network level.
- **SQLite everywhere** — Zero-config database. Main DB, queue DB, and cache all use SQLite. Simplifies deployment.
- **Dual JS pipelines** — Importmap for lightweight Stimulus controllers (no build step), esbuild only for the heavy Three.js graph bundle.
- **Version snapshots as JSON** — Full idea state serialized to JSON on each save. Enables diff and restore without complex schema versioning.
- **Topology = hierarchical tags** — Self-referential tree structure with color and type. More expressive than flat tags.
