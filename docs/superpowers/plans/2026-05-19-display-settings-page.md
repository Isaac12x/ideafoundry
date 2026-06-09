# Display Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move display settings (quote + contrast) to a dedicated `/settings/display` page with a continuous contrast range slider (70–150, default 100).

**Architecture:** Change contrast storage from a string enum (`normal`/`high`) to an integer (70–150). Apply contrast via a CSS custom property `--contrast` set as inline style on `<body>`, consumed by `main.app-main { filter: contrast(var(--contrast)) }`. A Stimulus controller drives the live preview slider.

**Tech Stack:** Rails 7 (ERB, Stimulus, importmap), Ruby, Minitest

---

## Files

| Action | Path |
|--------|------|
| Modify | `app/models/user.rb` |
| Modify | `app/assets/stylesheets/application.css` |
| Modify | `app/views/layouts/application.html.erb` |
| Modify | `config/routes.rb` |
| Modify | `app/controllers/settings_controller.rb` |
| Modify | `app/views/settings/index.html.erb` |
| Create | `app/views/settings/display.html.erb` |
| Create | `app/javascript/controllers/contrast_controller.js` |
| Modify | `test/controllers/settings_controller_test.rb` |

---

### Task 1: Update User model — integer contrast storage

**Files:**
- Modify: `app/models/user.rb`

- [ ] **Step 1: Write failing test for integer contrast storage**

In `test/controllers/settings_controller_test.rb`, add after the existing display tests:

```ruby
test "display_contrast returns 100 by default" do
  @user.update!(settings: {})
  assert_equal 100, @user.display_contrast
end

test "display_contrast migrates legacy 'high' to 130" do
  @user.update!(settings: { 'display_contrast' => 'high' })
  assert_equal 130, @user.display_contrast
end

test "display_contrast migrates legacy 'normal' to 100" do
  @user.update!(settings: { 'display_contrast' => 'normal' })
  assert_equal 100, @user.display_contrast
end

test "display_contrast returns stored integer value" do
  @user.update!(settings: { 'display_contrast' => '120' })
  assert_equal 120, @user.display_contrast
end

test "display_contrast clamps out-of-range value to 100" do
  @user.update!(settings: { 'display_contrast' => '999' })
  assert_equal 100, @user.display_contrast
end
```

- [ ] **Step 2: Run tests to confirm failure**

```
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: failures on the new tests (display_contrast returns String 'normal' not Integer 100).

- [ ] **Step 3: Update `user.rb` — remove enum, replace with integer logic**

In `app/models/user.rb`, replace lines:

```ruby
ALLOWED_CONTRAST_VALUES = %w[normal high].freeze
```

with nothing (delete the line).

Replace the `display_contrast` method (lines ~552–555):

```ruby
def display_contrast
  val = settings&.dig('display_contrast').to_s
  ALLOWED_CONTRAST_VALUES.include?(val) ? val : 'normal'
end
```

with:

```ruby
def display_contrast
  val = settings&.dig('display_contrast').to_s
  return 130 if val == 'high'
  return 100 if val == 'normal' || val.empty?
  int = val.to_i
  int.between?(70, 150) ? int : 100
end
```

Replace the contrast logic inside `update_display_quote` (lines ~569–573):

```ruby
if ALLOWED_CONTRAST_VALUES.include?(contrast) && contrast != 'normal'
  self.settings['display_contrast'] = contrast
else
  self.settings.delete('display_contrast')
end
```

with:

```ruby
contrast_int = contrast.to_i.clamp(70, 150)
if contrast_int == 100
  self.settings.delete('display_contrast')
else
  self.settings['display_contrast'] = contrast_int.to_s
end
```

Also update the `contrast = h.fetch(...)` line above it (line ~560):

```ruby
contrast = h.fetch('contrast', '100').to_s.strip
```

(Change default from `'normal'` to `'100'`.)

- [ ] **Step 4: Run tests to confirm passage**

```
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: all new tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb test/controllers/settings_controller_test.rb
git commit -m "refactor: store display contrast as integer (70-150), migrate legacy enum values"
```

---

### Task 2: Add routes and controller action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/settings_controller.rb`

- [ ] **Step 1: Write failing route test**

In `test/controllers/settings_controller_test.rb`, add:

```ruby
test "GET settings/display renders display page" do
  get settings_display_path
  assert_response :success
end

test "PATCH settings/display updates contrast and redirects to display page" do
  patch settings_display_path, params: {
    display_settings: { quote: "Keep it simple.", contrast: "120" }
  }
  assert_redirected_to settings_display_path
  @user.reload
  assert_equal 120, @user.display_contrast
  assert_equal "Keep it simple.", @user.display_quote
end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: `NameError: undefined local variable or method 'settings_display_path'`

- [ ] **Step 3: Add routes**

In `config/routes.rb`, after line `patch 'settings', to: 'settings#update_display'` (line 126), add:

```ruby
get 'settings/display', to: 'settings#display', as: :settings_display
patch 'settings/display', to: 'settings#update_display'
```

- [ ] **Step 4: Add `display` action to controller**

In `app/controllers/settings_controller.rb`, add after the `index` action (after line 7):

```ruby
def display
  @display_quote = @user.display_quote
  @display_contrast = @user.display_contrast
end
```

- [ ] **Step 5: Update `update_display` redirect**

In `app/controllers/settings_controller.rb`, in `update_display`, change:

```ruby
redirect_to settings_path, notice: 'Display quote updated.'
```

to:

```ruby
redirect_to settings_display_path, notice: 'Display settings updated.'
```

Also update the render fallback:

```ruby
render :index, status: :unprocessable_content
```

to:

```ruby
render :display, status: :unprocessable_content
```

- [ ] **Step 6: Run tests**

```
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: new route/controller tests pass. The existing test `"PATCH settings updates display quote"` that patches `settings_path` may still pass (old route kept) but redirects to `settings_display_path` now — update that test's assertion:

Find in test file:
```ruby
assert_redirected_to settings_path
```

Change to:
```ruby
assert_redirected_to settings_display_path
```

Run again:
```
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb test/controllers/settings_controller_test.rb
git commit -m "feat: add GET/PATCH settings/display route and controller action"
```

---

### Task 3: Create the display settings view

**Files:**
- Create: `app/views/settings/display.html.erb`
- Create: `app/javascript/controllers/contrast_controller.js`

- [ ] **Step 1: Create Stimulus contrast controller**

Create `app/javascript/controllers/contrast_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "input"]

  connect() {
    this.sync()
  }

  sync() {
    const value = this.inputTarget.value
    this.outputTarget.textContent = value + "%"
    document.body.style.setProperty("--contrast", value + "%")
  }
}
```

- [ ] **Step 2: Create display view**

Create `app/views/settings/display.html.erb`:

```erb
<div class="settings-container">
  <div class="page-header">
    <h2>Display</h2>
    <div class="header-actions">
      <%= link_to settings_path, class: "btn btn-sm" do %>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
        Back to Settings
      <% end %>
    </div>
  </div>

  <%= form_with url: settings_display_path, method: :patch, local: true do |form| %>
    <div class="config-section">
      <h3>Quote</h3>
      <p class="config-description">Text shown at the top of every page.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label" for="display_settings_quote">Page Quote</label>
          <%= text_area_tag "display_settings[quote]",
                            @display_quote,
                            id: "display_settings_quote",
                            rows: 2,
                            class: "form-control",
                            placeholder: "A useful reminder for the top of the page" %>
        </div>
      </div>
    </div>

    <div class="config-section" data-controller="contrast">
      <h3>Contrast</h3>
      <p class="config-description">Adjust display contrast. Preview updates in real time.</p>

      <div class="weight-grid">
        <div class="weight-item">
          <label class="weight-label">
            Contrast level: <span data-contrast-target="output"><%= @display_contrast %>%</span>
          </label>
          <%= range_field_tag "display_settings[contrast]",
                              @display_contrast,
                              min: 70,
                              max: 150,
                              step: 1,
                              class: "form-control-range",
                              data: {
                                contrast_target: "input",
                                action: "input->contrast#sync"
                              } %>
        </div>
      </div>
    </div>

    <div class="config-actions">
      <%= form.submit "Save Display", class: "btn btn-primary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Verify the view renders**

```
bin/rails test test/controllers/settings_controller_test.rb -n "test_GET_settings/display_renders_display_page"
```

Expected: pass (green).

- [ ] **Step 4: Commit**

```bash
git add app/views/settings/display.html.erb app/javascript/controllers/contrast_controller.js
git commit -m "feat: add display settings page with contrast range slider"
```

---

### Task 4: Apply contrast via CSS custom property

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add `--contrast` inline style to body in layout**

In `app/views/layouts/application.html.erb`, find:

```erb
  <body class="<%= body_class %>"
        data-contrast="<%= display_contrast.presence || 'normal' %>"
```

Change to:

```erb
  <body class="<%= body_class %>"
        data-contrast="<%= display_contrast.presence || 'normal' %>"
        style="--contrast: <%= (@user&.display_contrast || 100) %>%"
```

- [ ] **Step 2: Replace static high-contrast CSS with dynamic filter rule**

In `app/assets/stylesheets/application.css`, find and replace:

```css
/* High contrast mode */
body[data-contrast="high"] {
  --bg-base: #000000;
  --bg-surface: #0a0a0a;
  --bg-elevated: #111111;
  --bg-overlay: #1a1a1a;
  --bg-input: #0d0d0d;
  --border-default: #555566;
  --border-subtle: #3a3a4a;
  --border-emphasis: #7777aa;
  --text-primary: #ffffff;
  --text-secondary: #cccccc;
  --text-muted: #888899;
  --accent: #e8a83e;
  --accent-hover: #f5bc50;
}
```

with:

```css
main.app-main {
  filter: contrast(var(--contrast, 100%));
}
```

- [ ] **Step 3: Run full test suite to catch regressions**

```
bin/rails test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb app/assets/stylesheets/application.css
git commit -m "feat: apply contrast via CSS custom property on main content area"
```

---

### Task 5: Update settings index page

**Files:**
- Modify: `app/views/settings/index.html.erb`

- [ ] **Step 1: Write test for index changes**

In `test/controllers/settings_controller_test.rb`, add:

```ruby
test "GET settings does not render display quote form" do
  get settings_path
  assert_response :success
  assert_select "textarea[name=?]", "display_settings[quote]", count: 0
end

test "GET settings renders Display link" do
  get settings_path
  assert_response :success
  assert_select "a[href=?]", settings_display_path
end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/controllers/settings_controller_test.rb -n "test_GET_settings_does_not_render_display_quote_form"
```

Expected: FAIL (form still present).

- [ ] **Step 3: Update the existing `"GET settings renders display quote field"` test**

The existing test `"GET settings renders display quote field with current quote"` now expects the form to be on `/settings/display`, not `/settings`. Update it:

```ruby
test "GET settings/display renders display quote field with current quote" do
  @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

  get settings_display_path

  assert_response :success
  assert_select "textarea[name=?]", "display_settings[quote]" do |elements|
    assert_equal "Focus on the next useful thing.", elements.first.text
  end
end

test "GET settings/display renders configured quote banner" do
  @user.update!(settings: (@user.settings || {}).merge("display_quote" => { "text" => "Focus on the next useful thing." }))

  get settings_display_path

  assert_response :success
  assert_select "body > header.app-header ~ div.app-quote-banner", text: "Focus on the next useful thing."
end
```

(Replace the old `"GET settings renders display quote field with current quote"` and `"GET settings renders configured quote below navigation"` tests.)

- [ ] **Step 4: Modify `app/views/settings/index.html.erb`**

Remove the entire `display-quote-settings` section (lines 10–42):

```erb
  <section class="display-quote-settings">
    ...
  </section>
```

Add a "Display" settings-row at the top of the `settings-list` div, before the Scoring System link:

```erb
    <%= link_to settings_display_path, class: "settings-row" do %>
      <div class="settings-row-info">
        <h3>Display</h3>
        <p>Quote and contrast settings</p>
      </div>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>
    <% end %>
```

- [ ] **Step 5: Run full test suite**

```
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/settings/index.html.erb test/controllers/settings_controller_test.rb
git commit -m "feat: move display settings to /settings/display; add Display link to settings index"
```
