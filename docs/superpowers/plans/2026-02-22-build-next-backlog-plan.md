# Build Next Backlog — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a global "Build Next" backlog — lightweight items with title, description, drag-drop ordering, and done/undone state.

**Architecture:** New `BuildItem` model + `BuildItemsController` + dedicated page at `/build_items`. Reuses existing HTML5 drag-drop pattern (Stimulus `drag` controller adapted into a new `build_item_sort` controller for single-list reordering). Turbo Streams for all mutations.

**Tech Stack:** Rails 8, SQLite, Stimulus, Turbo Streams, custom CSS (Dark Forge design system)

---

### Task 1: Migration + Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_build_items.rb`
- Create: `app/models/build_item.rb`
- Create: `test/models/build_item_test.rb`
- Create: `test/fixtures/build_items.yml`
- Modify: `app/models/user.rb:3` (add `has_many`)

**Step 1: Write failing tests**

```ruby
# test/models/build_item_test.rb
require "test_helper"

class BuildItemTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "valid with title and user" do
    item = BuildItem.new(user: @user, title: "Add dark mode")
    assert item.valid?
  end

  test "invalid without title" do
    item = BuildItem.new(user: @user, title: nil)
    assert_not item.valid?
  end

  test "invalid without user" do
    item = BuildItem.new(title: "Something")
    assert_not item.valid?
  end

  test "sets position automatically" do
    item = BuildItem.create!(user: @user, title: "First")
    assert_equal 1, item.position
    item2 = BuildItem.create!(user: @user, title: "Second")
    assert_equal 2, item2.position
  end

  test "pending scope returns incomplete items ordered by position" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 2)
    i2 = BuildItem.create!(user: @user, title: "B", position: 1)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3, completed: true, completed_at: Time.current)
    result = @user.build_items.pending
    assert_equal [i2, i1], result.to_a
  end

  test "completed scope returns done items" do
    i1 = BuildItem.create!(user: @user, title: "Done", completed: true, completed_at: Time.current)
    i2 = BuildItem.create!(user: @user, title: "Not done")
    result = @user.build_items.done
    assert_equal [i1], result.to_a
  end

  test "mark_completed! sets completed and timestamp" do
    item = BuildItem.create!(user: @user, title: "Todo")
    item.mark_completed!
    assert item.completed
    assert_not_nil item.completed_at
  end

  test "mark_pending! clears completed" do
    item = BuildItem.create!(user: @user, title: "Todo", completed: true, completed_at: Time.current)
    item.mark_pending!
    assert_not item.completed
    assert_nil item.completed_at
  end
end
```

**Step 2: Run tests — expect failure** (model doesn't exist yet)

```bash
bin/rails test test/models/build_item_test.rb
```

**Step 3: Generate migration**

```bash
bin/rails generate migration CreateBuildItems user:references title:string description:text position:integer completed:boolean completed_at:datetime
```

Then edit the migration to add defaults and indexes:

```ruby
class CreateBuildItems < ActiveRecord::Migration[8.0]
  def change
    create_table :build_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :position
      t.boolean :completed, default: false, null: false
      t.datetime :completed_at

      t.timestamps
    end
    add_index :build_items, [:user_id, :position]
    add_index :build_items, [:user_id, :completed]
  end
end
```

**Step 4: Create model**

```ruby
# app/models/build_item.rb
class BuildItem < ApplicationRecord
  belongs_to :user

  validates :title, presence: true

  scope :pending, -> { where(completed: false).order(:position) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  before_validation :set_position, on: :create

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
  end

  private

  def set_position
    return if position.present? || user.nil?
    max = user.build_items.maximum(:position) || 0
    self.position = max + 1
  end
end
```

**Step 5: Add `has_many` to User**

In `app/models/user.rb`, add after line 6 (`has_many :topologies`):

```ruby
has_many :build_items, dependent: :destroy
```

**Step 6: Create fixture**

```yaml
# test/fixtures/build_items.yml
# (empty — tests create their own)
```

**Step 7: Run migration and tests**

```bash
bin/rails db:migrate && bin/rails test test/models/build_item_test.rb
```

Expected: ALL PASS

**Step 8: Commit**

```bash
git add -A && git commit -m "feat: add BuildItem model with migration, tests"
```

---

### Task 2: Controller + Routes

**Files:**
- Create: `app/controllers/build_items_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/build_items_controller_test.rb`

**Step 1: Write failing controller tests**

```ruby
# test/controllers/build_items_controller_test.rb
require "test_helper"

class BuildItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
  end

  test "GET index" do
    BuildItem.create!(user: @user, title: "Item 1")
    get build_items_path
    assert_response :success
    assert_select ".build-item", 1
  end

  test "POST create with valid params" do
    assert_difference("BuildItem.count", 1) do
      post build_items_path, params: { build_item: { title: "New item" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "POST create with blank title" do
    assert_no_difference("BuildItem.count") do
      post build_items_path, params: { build_item: { title: "" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "PATCH update" do
    item = BuildItem.create!(user: @user, title: "Old")
    patch build_item_path(item), params: { build_item: { title: "New" } }, as: :turbo_stream
    assert_response :success
    assert_equal "New", item.reload.title
  end

  test "DELETE destroy" do
    item = BuildItem.create!(user: @user, title: "Delete me")
    assert_difference("BuildItem.count", -1) do
      delete build_item_path(item), as: :turbo_stream
    end
    assert_response :success
  end

  test "PATCH toggle marks complete" do
    item = BuildItem.create!(user: @user, title: "Toggle me")
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert item.reload.completed
  end

  test "PATCH toggle marks pending" do
    item = BuildItem.create!(user: @user, title: "Toggle me", completed: true, completed_at: Time.current)
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert_not item.reload.completed
  end

  test "PATCH reorder updates positions" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 1)
    i2 = BuildItem.create!(user: @user, title: "B", position: 2)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3)
    patch reorder_build_items_path, params: { order: [i3.id, i1.id, i2.id] }, as: :turbo_stream
    assert_response :success
    assert_equal 1, i3.reload.position
    assert_equal 2, i1.reload.position
    assert_equal 3, i2.reload.position
  end
end
```

**Step 2: Run tests — expect failure**

```bash
bin/rails test test/controllers/build_items_controller_test.rb
```

**Step 3: Add routes**

In `config/routes.rb`, add before the `root` line:

```ruby
# Build Next backlog
resources :build_items, except: [:show] do
  member do
    patch :toggle
  end
  collection do
    patch :reorder
  end
end
```

**Step 4: Create controller**

```ruby
# app/controllers/build_items_controller.rb
class BuildItemsController < ApplicationController
  before_action :set_user
  before_action :set_build_item, only: [:edit, :update, :destroy, :toggle]

  def index
    @build_items = @user.build_items.pending
    @completed_items = @user.build_items.done
    @build_item = @user.build_items.build
  end

  def create
    @build_item = @user.build_items.build(build_item_params)

    if @build_item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_form", partial: "build_items/form", locals: { build_item: @build_item }), status: :unprocessable_entity }
        format.html { redirect_to build_items_path, alert: @build_item.errors.full_messages.join(", ") }
      end
    end
  end

  def edit
  end

  def update
    if @build_item.update(build_item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }), status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @build_item.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path, notice: "Item removed." }
    end
  end

  def toggle
    if @build_item.completed?
      @build_item.mark_pending!
    else
      @build_item.mark_completed!
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path }
    end
  end

  def reorder
    order = params[:order] || []
    ActiveRecord::Base.transaction do
      order.each_with_index do |id, index|
        @user.build_items.where(id: id).update_all(position: index + 1)
      end
    end

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json { head :ok }
    end
  end

  private

  def set_build_item
    @build_item = @user.build_items.find(params[:id])
  end

  def build_item_params
    params.require(:build_item).permit(:title, :description)
  end
end
```

**Step 5: Run tests**

```bash
bin/rails test test/controllers/build_items_controller_test.rb
```

Tests will still fail (missing views). That's expected — proceed to Task 3.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add BuildItemsController with routes, tests"
```

---

### Task 3: Views + Turbo Streams

**Files:**
- Create: `app/views/build_items/index.html.erb`
- Create: `app/views/build_items/_build_item.html.erb`
- Create: `app/views/build_items/_form.html.erb`
- Create: `app/views/build_items/_edit_form.html.erb`
- Create: `app/views/build_items/create.turbo_stream.erb`
- Create: `app/views/build_items/update.turbo_stream.erb`
- Create: `app/views/build_items/destroy.turbo_stream.erb`
- Create: `app/views/build_items/toggle.turbo_stream.erb`

**Step 1: Create index view**

```erb
<%# app/views/build_items/index.html.erb %>
<div class="build-items-container">
  <div class="page-header">
    <h2>Build Next</h2>
  </div>

  <div id="build_item_form">
    <%= render "form", build_item: @build_item %>
  </div>

  <div id="build_items_list"
       class="build-items-list"
       data-controller="build-item-sort"
       data-build-item-sort-url-value="<%= reorder_build_items_path %>">
    <% @build_items.each do |item| %>
      <%= render "build_item", build_item: item %>
    <% end %>

    <% if @build_items.empty? %>
      <div id="build_items_empty" class="empty-state">
        <p>Nothing here yet. What should you build next?</p>
      </div>
    <% end %>
  </div>

  <div class="completed-toggle-container" data-controller="completed-toggle">
    <button class="btn btn-sm completed-toggle-btn" data-action="click->completed-toggle#toggle">
      <svg class="chevron-icon" data-completed-toggle-target="icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>
      Show completed (<%= @completed_items.size %>)
    </button>

    <div class="completed-items" data-completed-toggle-target="list" id="completed_build_items">
      <% @completed_items.each do |item| %>
        <%= render "build_item", build_item: item %>
      <% end %>
    </div>
  </div>
</div>
```

**Step 2: Create _build_item partial**

```erb
<%# app/views/build_items/_build_item.html.erb %>
<div class="build-item <%= 'build-item--completed' if build_item.completed? %>"
     id="build_item_<%= build_item.id %>"
     data-build-item-sort-target="item"
     data-item-id="<%= build_item.id %>"
     data-position="<%= build_item.position %>"
     draggable="<%= build_item.completed? ? 'false' : 'true' %>">

  <% unless build_item.completed? %>
    <div class="drag-handle" title="Drag to reorder">&#8942;&#8942;</div>
  <% end %>

  <div class="build-item-checkbox">
    <%= button_to toggle_build_item_path(build_item), method: :patch, class: "checkbox-btn", data: { turbo_stream: true } do %>
      <% if build_item.completed? %>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="var(--accent)" stroke="var(--accent)" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="3"/><polyline points="9 11 12 14 16 10" stroke="var(--bg-base)" fill="none"/></svg>
      <% else %>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--border-emphasis)" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="3"/></svg>
      <% end %>
    <% end %>
  </div>

  <div class="build-item-content">
    <span class="build-item-title"><%= build_item.title %></span>
    <% if build_item.description.present? %>
      <span class="build-item-description"><%= truncate(build_item.description, length: 120) %></span>
    <% end %>
  </div>

  <div class="build-item-actions">
    <% unless build_item.completed? %>
      <button class="btn btn-sm btn-icon" data-action="click->inline-edit#start" data-inline-edit-target="editBtn" data-build-item-id="<%= build_item.id %>">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
      </button>
    <% end %>
    <%= button_to build_item_path(build_item), method: :delete, class: "btn btn-sm btn-icon btn-danger", data: { turbo_stream: true, turbo_confirm: "Delete this item?" } do %>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/></svg>
    <% end %>
  </div>
</div>
```

**Step 3: Create _form partial**

```erb
<%# app/views/build_items/_form.html.erb %>
<%= form_with(model: build_item, class: "build-item-form", data: { controller: "build-item-form", action: "turbo:submit-end->build-item-form#reset" }) do |f| %>
  <div class="build-item-form-row">
    <%= f.text_field :title, placeholder: "What should you build next?", class: "input build-item-input", required: true, data: { build_item_form_target: "input" } %>
    <%= f.submit "Add", class: "btn btn-primary" %>
  </div>
  <div class="build-item-form-desc" data-build-item-form-target="descRow" style="display:none;">
    <%= f.text_area :description, placeholder: "Optional details...", class: "input build-item-textarea", rows: 2 %>
  </div>
  <button type="button" class="btn btn-sm build-item-desc-toggle" data-action="click->build-item-form#toggleDesc" data-build-item-form-target="descToggle">+ Add description</button>
<% end %>
```

**Step 4: Create _edit_form partial**

```erb
<%# app/views/build_items/_edit_form.html.erb %>
<div class="build-item build-item--editing" id="build_item_<%= build_item.id %>">
  <%= form_with(model: build_item, class: "build-item-edit-form") do |f| %>
    <div class="build-item-edit-fields">
      <%= f.text_field :title, class: "input", autofocus: true %>
      <%= f.text_area :description, class: "input build-item-textarea", rows: 2, placeholder: "Optional details..." %>
    </div>
    <div class="build-item-edit-actions">
      <%= f.submit "Save", class: "btn btn-primary btn-sm" %>
      <button type="button" class="btn btn-sm" data-action="click->inline-edit#cancel">Cancel</button>
    </div>
  <% end %>
</div>
```

**Step 5: Create Turbo Stream templates**

```erb
<%# app/views/build_items/create.turbo_stream.erb %>
<%= turbo_stream.append "build_items_list" do %>
  <%= render "build_item", build_item: @build_item %>
<% end %>

<%= turbo_stream.remove "build_items_empty" %>

<%= turbo_stream.replace "build_item_form" do %>
  <%= render "form", build_item: @user.build_items.build %>
<% end %>
```

```erb
<%# app/views/build_items/update.turbo_stream.erb %>
<%= turbo_stream.replace "build_item_#{@build_item.id}" do %>
  <%= render "build_item", build_item: @build_item %>
<% end %>
```

```erb
<%# app/views/build_items/destroy.turbo_stream.erb %>
<%= turbo_stream.remove "build_item_#{@build_item.id}" %>
```

```erb
<%# app/views/build_items/toggle.turbo_stream.erb %>
<% if @build_item.completed? %>
  <%# Moved to completed — remove from active list, prepend to completed %>
  <%= turbo_stream.remove "build_item_#{@build_item.id}" %>
  <%= turbo_stream.prepend "completed_build_items" do %>
    <%= render "build_item", build_item: @build_item %>
  <% end %>
<% else %>
  <%# Moved back to active — remove from completed, append to active list %>
  <%= turbo_stream.remove "build_item_#{@build_item.id}" %>
  <%= turbo_stream.append "build_items_list" do %>
    <%= render "build_item", build_item: @build_item %>
  <% end %>
<% end %>
```

**Step 6: Run controller tests again**

```bash
bin/rails test test/controllers/build_items_controller_test.rb
```

Expected: ALL PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add Build Next views with Turbo Streams"
```

---

### Task 4: Stimulus Controllers

**Files:**
- Create: `app/javascript/controllers/build_item_sort_controller.js`
- Create: `app/javascript/controllers/build_item_form_controller.js`
- Create: `app/javascript/controllers/completed_toggle_controller.js`
- Create: `app/javascript/controllers/inline_edit_controller.js`

**Step 1: Create build_item_sort_controller.js** (drag-drop reorder within single list)

```javascript
// app/javascript/controllers/build_item_sort_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  connect() {
    this.setupDragAndDrop()
  }

  setupDragAndDrop() {
    this.itemTargets.forEach(item => {
      if (item.draggable) {
        item.addEventListener("dragstart", this.handleDragStart.bind(this))
        item.addEventListener("dragend", this.handleDragEnd.bind(this))
      }
    })
    this.element.addEventListener("dragover", this.handleDragOver.bind(this))
    this.element.addEventListener("drop", this.handleDrop.bind(this))
  }

  itemTargetConnected(element) {
    if (element.draggable) {
      element.addEventListener("dragstart", this.handleDragStart.bind(this))
      element.addEventListener("dragend", this.handleDragEnd.bind(this))
    }
  }

  handleDragStart(event) {
    this.draggedElement = event.currentTarget
    event.currentTarget.classList.add("dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", event.currentTarget.dataset.itemId)
  }

  handleDragEnd(event) {
    event.currentTarget.classList.remove("dragging")
    this.draggedElement = null
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const afterElement = this.getDragAfterElement(event.clientY)
    if (afterElement) {
      this.element.insertBefore(this.draggedElement, afterElement)
    } else {
      // Append after last item target (but before non-item elements)
      const lastItem = this.itemTargets[this.itemTargets.length - 1]
      if (lastItem && lastItem !== this.draggedElement) {
        lastItem.after(this.draggedElement)
      }
    }
  }

  handleDrop(event) {
    event.preventDefault()
    this.saveOrder()
  }

  getDragAfterElement(y) {
    const items = this.itemTargets.filter(el => el !== this.draggedElement)
    return items.reduce((closest, child) => {
      const box = child.getBoundingClientRect()
      const offset = y - box.top - box.height / 2
      if (offset < 0 && offset > closest.offset) {
        return { offset, element: child }
      }
      return closest
    }, { offset: Number.NEGATIVE_INFINITY }).element
  }

  async saveOrder() {
    const order = this.itemTargets.map(el => el.dataset.itemId)
    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ order })
    })
  }
}
```

**Step 2: Create build_item_form_controller.js**

```javascript
// app/javascript/controllers/build_item_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "descRow", "descToggle"]

  reset() {
    this.element.reset()
    if (this.hasDescRowTarget) {
      this.descRowTarget.style.display = "none"
    }
    if (this.hasInputTarget) {
      this.inputTarget.focus()
    }
  }

  toggleDesc() {
    if (this.hasDescRowTarget) {
      const hidden = this.descRowTarget.style.display === "none"
      this.descRowTarget.style.display = hidden ? "block" : "none"
      if (this.hasDescToggleTarget) {
        this.descToggleTarget.textContent = hidden ? "- Hide description" : "+ Add description"
      }
    }
  }
}
```

**Step 3: Create completed_toggle_controller.js**

```javascript
// app/javascript/controllers/completed_toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon"]

  toggle() {
    const list = this.listTarget
    const isHidden = list.classList.contains("completed-items--hidden") || !list.classList.contains("completed-items--visible")

    if (isHidden) {
      list.classList.remove("completed-items--hidden")
      list.classList.add("completed-items--visible")
      this.iconTarget.style.transform = "rotate(180deg)"
    } else {
      list.classList.remove("completed-items--visible")
      list.classList.add("completed-items--hidden")
      this.iconTarget.style.transform = "rotate(0deg)"
    }
  }
}
```

**Step 4: Create inline_edit_controller.js**

```javascript
// app/javascript/controllers/inline_edit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  start(event) {
    const buildItemId = event.currentTarget.dataset.buildItemId
    const itemEl = document.getElementById(`build_item_${buildItemId}`)
    if (!itemEl) return

    // Fetch the edit form via turbo
    fetch(`/build_items/${buildItemId}/edit`, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    }).then(r => r.text()).then(html => {
      Turbo.renderStreamMessage(html)
    })
  }

  cancel() {
    // Reload page to restore original state — simplest approach
    window.location.reload()
  }
}
```

Actually, let's simplify — make edit return a turbo_stream that replaces the item with the edit form:

Add to controller `edit` action:

```ruby
def edit
  respond_to do |format|
    format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }) }
    format.html
  end
end
```

And simplify inline_edit_controller:

```javascript
// app/javascript/controllers/inline_edit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async start(event) {
    const id = event.currentTarget.dataset.buildItemId
    const response = await fetch(`/build_items/${id}/edit`, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    const html = await response.text()
    Turbo.renderStreamMessage(html)
  }

  cancel(event) {
    // Reload to restore — simple and reliable
    Turbo.visit(window.location.href)
  }
}
```

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add Stimulus controllers for drag-drop, form, toggle, inline edit"
```

---

### Task 5: CSS Styles

**Files:**
- Create: `app/assets/stylesheets/build_items.css`

**Step 1: Create stylesheet**

```css
/* app/assets/stylesheets/build_items.css */

/* ============================================
   Build Next Backlog — "Dark Forge" Theme
   ============================================ */

.build-items-container {
  max-width: 720px;
  margin: 0 auto;
  padding: 24px;
}

/* ---- Add Form ---- */
.build-item-form {
  margin-bottom: 24px;
}

.build-item-form-row {
  display: flex;
  gap: 8px;
}

.build-item-input {
  flex: 1;
}

.build-item-form-desc {
  margin-top: 8px;
}

.build-item-textarea {
  width: 100%;
  resize: vertical;
}

.build-item-desc-toggle {
  margin-top: 4px;
  color: var(--text-muted);
  font-size: 0.75rem;
}

/* ---- Item List ---- */
.build-items-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-height: 40px;
}

/* ---- Single Item ---- */
.build-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background: var(--bg-elevated);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-sm);
  transition: all 0.2s;
}

.build-item:hover {
  border-color: var(--border-emphasis);
  box-shadow: var(--shadow-sm);
}

.build-item .drag-handle {
  cursor: grab;
  color: var(--text-muted);
  padding: 2px 4px;
  font-size: 0.8rem;
  user-select: none;
}

.build-item .drag-handle:active { cursor: grabbing; }

.build-item-checkbox {
  flex-shrink: 0;
}

.checkbox-btn {
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  display: flex;
  align-items: center;
  line-height: 1;
}

.build-item-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.build-item-title {
  font-weight: 500;
  font-size: 0.9rem;
  color: var(--text-primary);
}

.build-item-description {
  font-size: 0.75rem;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.build-item-actions {
  display: flex;
  gap: 4px;
  opacity: 0;
  transition: opacity 0.15s;
  flex-shrink: 0;
}

.build-item:hover .build-item-actions {
  opacity: 1;
}

.btn-icon {
  padding: 4px 6px;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* ---- Completed State ---- */
.build-item--completed {
  opacity: 0.5;
}

.build-item--completed .build-item-title {
  text-decoration: line-through;
  color: var(--text-muted);
}

.build-item--completed .build-item-description {
  text-decoration: line-through;
}

.build-item--completed:hover {
  border-color: var(--border-default);
  box-shadow: none;
}

/* ---- Completed Toggle ---- */
.completed-toggle-container {
  margin-top: 32px;
  border-top: 1px solid var(--border-subtle);
  padding-top: 16px;
}

.completed-toggle-btn {
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 0.8rem;
}

.chevron-icon {
  transition: transform 0.2s;
}

.completed-items {
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.3s ease;
}

.completed-items--visible {
  max-height: 2000px;
}

.completed-items--hidden {
  max-height: 0;
}

/* ---- Edit Form Inline ---- */
.build-item--editing {
  background: var(--bg-overlay);
  border-color: var(--accent);
  padding: 12px;
}

.build-item-edit-fields {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 8px;
}

.build-item-edit-actions {
  display: flex;
  gap: 6px;
}

/* ---- Drag States ---- */
.build-item.dragging {
  opacity: 0.4;
  transform: rotate(2deg);
}

/* ---- Empty State ---- */
.build-items-container .empty-state {
  text-align: center;
  padding: 40px 20px;
  color: var(--text-muted);
}

/* ---- Responsive ---- */
@media (max-width: 768px) {
  .build-items-container { padding: 16px; }
  .build-item-actions { opacity: 1; }
}
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add Build Next CSS styles"
```

---

### Task 6: Navigation + Final Integration

**Files:**
- Modify: `app/views/layouts/application.html.erb:31-34` (add nav pill)

**Step 1: Add nav pill**

After the Topologies nav pill (line 34) and before the Settings nav pill, add:

```erb
<%= link_to build_items_path, class: "nav-pill #{controller_name == 'build_items' ? 'active' : ''}" do %>
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 013 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
  Build Next
<% end %>
```

**Step 2: Run full test suite**

```bash
bin/rails test
```

Expected: ALL PASS

**Step 3: Manual smoke test**

```bash
bin/rails server
```

Visit `http://localhost:3000/build_items` and verify:
- Add form works (creates item, clears form)
- Drag-drop reorders items
- Checkbox marks done (item moves to completed)
- Show completed toggle works with slide animation
- Edit inline works
- Delete works
- Nav pill is active on this page

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add Build Next nav link, complete feature integration"
```
