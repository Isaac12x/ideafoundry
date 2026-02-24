# Email Template Themes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 5 selectable visual themes (dark, light, minimal, bold, corporate) for share + notification emails, configurable in /settings/email.

**Architecture:** A helper module defines theme color palettes as frozen hashes. Mailer actions look up the user's selected theme and pass it as `@theme` to ERB templates, which interpolate colors into inline styles. Theme selection stored in existing user settings JSON.

**Tech Stack:** Rails 8, Minitest, ERB mailer views, inline CSS

---

### Task 1: EmailThemeHelper module

**Files:**
- Create: `app/helpers/email_theme_helper.rb`
- Test: `test/helpers/email_theme_helper_test.rb`

**Step 1: Write the failing test**

```ruby
# test/helpers/email_theme_helper_test.rb
require "test_helper"

class EmailThemeHelperTest < ActiveSupport::TestCase
  test "THEMES contains all five theme keys" do
    assert_equal %w[bold corporate dark light minimal], EmailThemeHelper::THEMES.keys.sort
  end

  test "each theme has required color keys" do
    required = %i[bg text accent card_bg border muted]
    EmailThemeHelper::THEMES.each do |name, theme|
      required.each do |key|
        assert theme.key?(key), "Theme '#{name}' missing key :#{key}"
      end
    end
  end

  test "theme_for returns dark theme by default" do
    user = User.create!(email: "theme@test.com", name: "T")
    theme = EmailThemeHelper.theme_for(user)
    assert_equal "#14141a", theme[:bg]
  end

  test "theme_for returns selected theme" do
    user = User.create!(email: "theme2@test.com", name: "T")
    user.update_email_settings({ 'recipients' => '', 'from_email' => '', 'from_name' => '', 'template' => 'light' })
    theme = EmailThemeHelper.theme_for(user)
    assert_equal "#ffffff", theme[:bg]
    assert_equal "#2563eb", theme[:accent]
  end

  test "theme_for falls back to dark for unknown theme" do
    user = User.create!(email: "theme3@test.com", name: "T")
    user.update_email_settings({ 'recipients' => '', 'from_email' => '', 'from_name' => '', 'template' => 'nonexistent' })
    theme = EmailThemeHelper.theme_for(user)
    assert_equal "#14141a", theme[:bg]
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/email_theme_helper_test.rb`
Expected: FAIL — `uninitialized constant EmailThemeHelper`

**Step 3: Write the implementation**

```ruby
# app/helpers/email_theme_helper.rb
module EmailThemeHelper
  THEMES = {
    'dark' => {
      bg: '#14141a', text: '#ece8e1', accent: '#d4953a',
      card_bg: '#1c1c24', border: '#2a2a36', muted: '#9a9498'
    }.freeze,
    'light' => {
      bg: '#ffffff', text: '#1a1a2e', accent: '#2563eb',
      card_bg: '#f8f9fa', border: '#e2e8f0', muted: '#64748b'
    }.freeze,
    'minimal' => {
      bg: '#ffffff', text: '#333333', accent: '#333333',
      card_bg: 'transparent', border: '#eeeeee', muted: '#888888'
    }.freeze,
    'bold' => {
      bg: '#0f0f1a', text: '#f0f0f0', accent: '#ff6b35',
      card_bg: '#1a1a2e', border: '#2d2d44', muted: '#a0a0b0'
    }.freeze,
    'corporate' => {
      bg: '#f5f5f5', text: '#2c3e50', accent: '#1a5276',
      card_bg: '#ffffff', border: '#d5d8dc', muted: '#7f8c8d'
    }.freeze
  }.freeze

  DEFAULT_THEME = 'dark'

  def self.theme_for(user)
    key = user.email_settings['template'].presence || DEFAULT_THEME
    THEMES[key] || THEMES[DEFAULT_THEME]
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/helpers/email_theme_helper_test.rb`
Expected: PASS (all 5 tests)

**Step 5: Commit**

```bash
git add app/helpers/email_theme_helper.rb test/helpers/email_theme_helper_test.rb
git commit -m "feat: add EmailThemeHelper with 5 email themes"
```

---

### Task 2: User model — allow 'template' in email settings

**Files:**
- Modify: `app/models/user.rb:24-28` (DEFAULT_EMAIL_SETTINGS)
- Modify: `app/models/user.rb:80-83` (update_email_settings slice)
- Test: `test/models/user_test.rb`

**Step 1: Write the failing test**

Append to `test/models/user_test.rb`:

```ruby
test "email_settings includes template defaulting to dark" do
  @user.save!
  assert_equal 'dark', (@user.email_settings['template'] || 'dark')
end

test "update_email_settings persists template" do
  @user.save!
  @user.update_email_settings({ 'recipients' => 'a@b.com', 'from_email' => '', 'from_name' => '', 'template' => 'light' })
  @user.reload
  assert_equal 'light', @user.email_settings['template']
end

test "update_email_settings rejects unknown template keys" do
  @user.save!
  @user.update_email_settings({ 'recipients' => '', 'from_email' => '', 'from_name' => '', 'template' => 'light', 'hacker' => 'bad' })
  @user.reload
  assert_nil @user.email_settings['hacker']
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/user_test.rb`
Expected: second test FAILS — `template` not in slice so not persisted

**Step 3: Edit user.rb**

In `DEFAULT_EMAIL_SETTINGS`, add `'template' => 'dark'`:

```ruby
DEFAULT_EMAIL_SETTINGS = {
  'recipients' => '',
  'from_email' => '',
  'from_name' => '',
  'template' => 'dark'
}.freeze
```

In `update_email_settings`, add `'template'` to the slice:

```ruby
def update_email_settings(email_params)
  self.settings ||= {}
  self.settings['email'] = email_params.to_h.slice('recipients', 'from_email', 'from_name', 'template')
  save
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/user_test.rb`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "feat: add template key to email settings"
```

---

### Task 3: Settings controller + email_params permit

**Files:**
- Modify: `app/controllers/settings_controller.rb:215` (email_params)
- Modify: `app/controllers/settings_controller.rb:58-63` (email action)
- Test: `test/controllers/settings_controller_test.rb`

**Step 1: Write the failing test**

Append to `test/controllers/settings_controller_test.rb`:

```ruby
test "GET settings/email renders page" do
  get settings_email_path
  assert_response :success
end

test "PATCH settings/email saves template selection" do
  patch settings_email_path, params: {
    email_settings: { recipients: '', from_email: '', from_name: '', template: 'bold' }
  }
  assert_redirected_to settings_email_path
  @user.reload
  assert_equal 'bold', @user.email_settings['template']
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/settings_controller_test.rb`
Expected: template test FAILS — `template` not in permitted params

**Step 3: Edit settings_controller.rb**

In `email_params`:

```ruby
def email_params
  params.require(:email_settings).permit(:recipients, :from_email, :from_name, :template)
end
```

In `email` action, add `@available_themes`:

```ruby
def email
  @email_settings = @user.email_settings
  @notification_triggers = @user.notification_triggers
  @notification_content = @user.notification_content
  @inbound_address = Rails.application.credentials.dig(:resend, :inbound_address)
  @available_themes = EmailThemeHelper::THEMES
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/settings_controller_test.rb`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add app/controllers/settings_controller.rb test/controllers/settings_controller_test.rb
git commit -m "feat: permit template param in email settings controller"
```

---

### Task 4: Theme picker UI in /settings/email

**Files:**
- Modify: `app/views/settings/email.html.erb`

**Step 1: Add theme picker section**

Insert after `<h3>Email Configuration</h3>` description paragraph and before the `<div class="weight-grid">`, inside the existing form. Add a theme selector row:

```erb
<div style="margin-bottom: 1.5rem;">
  <label class="weight-label" style="margin-bottom: 0.75rem; display: block;">Email Theme</label>
  <span class="weight-description" style="display: block; margin-bottom: 0.75rem;">Choose a visual style for outgoing share and notification emails.</span>
  <div style="display: flex; gap: 0.75rem; flex-wrap: wrap;">
    <% @available_themes.each do |key, colors| %>
      <label style="cursor: pointer; display: block;">
        <input type="radio"
               name="email_settings[template]"
               value="<%= key %>"
               <%= 'checked' if @email_settings['template'].to_s == key || (@email_settings['template'].blank? && key == 'dark') %>
               style="display: none;">
        <div style="
          border: 2px solid <%= (@email_settings['template'].to_s == key || (@email_settings['template'].blank? && key == 'dark')) ? '#d4953a' : '#2a2a36' %>;
          border-radius: 8px;
          padding: 0.75rem 1rem;
          min-width: 110px;
          text-align: center;
          background: #1c1c24;
          transition: border-color 0.15s;
        ">
          <div style="display: flex; justify-content: center; gap: 6px; margin-bottom: 8px;">
            <span style="width: 18px; height: 18px; border-radius: 50%; background: <%= colors[:bg] %>; border: 1px solid #444; display: inline-block;"></span>
            <span style="width: 18px; height: 18px; border-radius: 50%; background: <%= colors[:accent] %>; display: inline-block;"></span>
            <span style="width: 18px; height: 18px; border-radius: 50%; background: <%= colors[:text] %>; border: 1px solid #444; display: inline-block;"></span>
          </div>
          <span style="font-size: 0.8rem; color: #ece8e1; text-transform: capitalize;"><%= key %></span>
        </div>
      </label>
    <% end %>
  </div>
</div>
```

**Step 2: Verify visually**

Run: `bin/rails server` — visit /settings/email, confirm 5 theme cards render, selected one has gold border, clicking saves.

**Step 3: Commit**

```bash
git add app/views/settings/email.html.erb
git commit -m "feat: add theme picker cards to email settings page"
```

---

### Task 5: Wire themes into mailer + update share_idea template

**Files:**
- Modify: `app/mailers/idea_mailer.rb` — set `@theme` in `share_idea`, `share_list`, `event_notification`
- Modify: `app/views/idea_mailer/share_idea.html.erb` — replace hardcoded colors with `@theme[:key]`

**Step 1: Edit idea_mailer.rb**

Add `@theme = EmailThemeHelper.theme_for(@user)` as the first line after `@user = ...` in `share_idea`, `share_list`, and `event_notification`.

```ruby
def share_idea(idea, recipient_email, sender_name: nil)
  @idea = idea
  @user = idea.user
  @theme = EmailThemeHelper.theme_for(@user)
  @sender_name = sender_name || @user.name
  # ... rest unchanged
end

def share_list(list, recipient_email, sender_name: nil)
  @list = list
  @ideas = list.ideas.includes(:topologies).order("idea_lists.position")
  @user = list.user
  @theme = EmailThemeHelper.theme_for(@user)
  @sender_name = sender_name || @user.name
  # ... rest unchanged
end

def event_notification(idea, recipient_email, event_type:, metadata: {})
  @idea = idea
  @user = idea.user
  @theme = EmailThemeHelper.theme_for(@user)
  @event_type = event_type
  # ... rest unchanged
end
```

**Step 2: Update share_idea.html.erb**

Replace all hardcoded color values:
- `#14141a` → `<%= @theme[:bg] %>`
- `#ece8e1` → `<%= @theme[:text] %>`
- `#d4953a` → `<%= @theme[:accent] %>`
- `#1c1c24` → `<%= @theme[:card_bg] %>`
- `#2a2a36` → `<%= @theme[:border] %>`
- `#9a9498` → `<%= @theme[:muted] %>`
- `#5c5860` → `<%= @theme[:muted] %>`

Full replacement (all style attributes use ERB interpolation):

```erb
<div style="max-width: 600px; margin: 0 auto; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: <%= @theme[:text] %>; background: <%= @theme[:bg] %>; padding: 2rem; border-radius: 10px;">
  <div style="border-bottom: 1px solid <%= @theme[:border] %>; padding-bottom: 1rem; margin-bottom: 1.5rem;">
    <h1 style="margin: 0; font-size: 1.5rem; font-weight: 400; font-style: italic; color: <%= @theme[:accent] %>;">
      <%= @idea.title %>
    </h1>
    <p style="margin: 6px 0 0; font-size: 0.85rem; color: <%= @theme[:muted] %>;">
      Shared by <%= @sender_name %> &middot; <%= @idea.state.humanize %>
    </p>
  </div>

  <% if @idea.computed_score.present? %>
    <div style="display: inline-block; background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 8px 16px; margin-bottom: 1.5rem;">
      <span style="font-size: 0.8rem; color: <%= @theme[:muted] %>;">Score</span>
      <span style="font-size: 1.2rem; font-weight: 600; color: <%= @theme[:accent] %>; margin-left: 8px;">
        <%= number_with_precision(@idea.computed_score, precision: 2) %>
      </span>
    </div>
  <% end %>

  <% if @idea.topologies.any? %>
    <div style="margin-bottom: 1rem;">
      <% @idea.topologies.each do |topology| %>
        <span style="display: inline-block; background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 4px; padding: 2px 8px; font-size: 0.8rem; color: <%= @theme[:muted] %>; margin-right: 4px;">
          <%= topology.name %>
        </span>
      <% end %>
    </div>
  <% end %>

  <% if @idea.description.present? %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1.25rem; margin-bottom: 1.5rem; color: <%= @theme[:text] %>; line-height: 1.6; font-size: 0.95rem;">
      <%= @idea.description %>
    </div>
  <% end %>

  <table style="width: 100%; border-collapse: collapse; margin-bottom: 1.5rem;">
    <tr>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">TRL</td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.trl || 0 %></td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Opportunity</td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.opportunity || 0 %></td>
    </tr>
    <tr>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Timing</td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.timing || 0 %></td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Difficulty</td>
      <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.difficulty || 0 %></td>
    </tr>
  </table>

  <div style="border-top: 1px solid <%= @theme[:border] %>; padding-top: 1rem; font-size: 0.8rem; color: <%= @theme[:muted] %>;">
    Created <%= @idea.created_at.strftime("%B %d, %Y") %> &middot;
    Attempt #<%= @idea.attempt_count %>
  </div>
</div>
```

**Step 3: Commit**

```bash
git add app/mailers/idea_mailer.rb app/views/idea_mailer/share_idea.html.erb
git commit -m "feat: wire theme colors into share_idea email template"
```

---

### Task 6: Update share_list template with theme colors

**Files:**
- Modify: `app/views/idea_mailer/share_list.html.erb`

**Step 1: Replace hardcoded colors**

Same substitution pattern as Task 5. Additionally `#24242e` (used for state/topology badges) maps to `@theme[:card_bg]`.

```erb
<div style="max-width: 600px; margin: 0 auto; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: <%= @theme[:text] %>; background: <%= @theme[:bg] %>; padding: 2rem; border-radius: 10px;">
  <div style="border-bottom: 1px solid <%= @theme[:border] %>; padding-bottom: 1rem; margin-bottom: 1.5rem;">
    <h1 style="margin: 0; font-size: 1.5rem; font-weight: 400; font-style: italic; color: <%= @theme[:accent] %>;">
      <%= @list.name %>
    </h1>
    <p style="margin: 6px 0 0; font-size: 0.85rem; color: <%= @theme[:muted] %>;">
      Shared by <%= @sender_name %> &middot; <%= @ideas.size %> idea<%= @ideas.size == 1 ? "" : "s" %>
    </p>
  </div>

  <% @ideas.each_with_index do |idea, idx| %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1rem 1.25rem; margin-bottom: 12px;">
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 6px;"><tr>
        <td style="vertical-align: baseline; width: 24px; color: <%= @theme[:muted] %>; font-size: 0.8rem;"><%= idx + 1 %>.</td>
        <td style="vertical-align: baseline;">
          <h2 style="margin: 0; font-size: 1.1rem; font-weight: 500; color: <%= @theme[:text] %>;"><%= idea.title %></h2>
        </td>
        <% if idea.computed_score.present? %>
          <td style="vertical-align: baseline; text-align: right; white-space: nowrap;">
            <span style="font-size: 0.85rem; font-weight: 600; color: <%= @theme[:accent] %>;"><%= number_with_precision(idea.computed_score, precision: 2) %></span>
          </td>
        <% end %>
      </tr></table>

      <div style="font-size: 0.8rem; color: <%= @theme[:muted] %>;">
        <span style="display: inline-block; background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 4px; padding: 1px 6px; margin-right: 6px;">
          <%= idea.state.humanize %>
        </span>
        <% idea.topologies.each do |topology| %>
          <span style="display: inline-block; background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 4px; padding: 1px 6px; margin-right: 4px;">
            <%= topology.name %>
          </span>
        <% end %>
      </div>

      <% if idea.description.present? %>
        <p style="margin: 8px 0 0; font-size: 0.85rem; color: <%= @theme[:muted] %>; line-height: 1.5;">
          <%= truncate(idea.description.to_plain_text, length: 200) %>
        </p>
      <% end %>
    </div>
  <% end %>

  <% if @ideas.empty? %>
    <div style="text-align: center; padding: 2rem; color: <%= @theme[:muted] %>;">
      This list has no ideas yet.
    </div>
  <% end %>

  <div style="border-top: 1px solid <%= @theme[:border] %>; padding-top: 1rem; font-size: 0.8rem; color: <%= @theme[:muted] %>;">
    Sent from Idea Foundry
  </div>
</div>
```

**Step 2: Commit**

```bash
git add app/views/idea_mailer/share_list.html.erb
git commit -m "feat: wire theme colors into share_list email template"
```

---

### Task 7: Update event_notification template with theme colors

**Files:**
- Modify: `app/views/idea_mailer/event_notification.html.erb`

**Step 1: Replace hardcoded colors**

Same substitution pattern. The `border-left: 3px solid #d4953a` on external content becomes `border-left: 3px solid <%= @theme[:accent] %>`.

```erb
<div style="max-width: 600px; margin: 0 auto; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: <%= @theme[:text] %>; background: <%= @theme[:bg] %>; padding: 2rem; border-radius: 10px;">
  <div style="border-bottom: 1px solid <%= @theme[:border] %>; padding-bottom: 1rem; margin-bottom: 1.5rem;">
    <p style="margin: 0 0 4px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; color: <%= @theme[:muted] %>;">
      <%= @event_type.humanize %>
    </p>
    <h1 style="margin: 0; font-size: 1.5rem; font-weight: 400; font-style: italic; color: <%= @theme[:accent] %>;">
      <%= @idea.title %>
    </h1>
    <p style="margin: 6px 0 0; font-size: 0.85rem; color: <%= @theme[:muted] %>;">
      <%= @idea.state.humanize %>
      <% if @idea.computed_score.present? && @content_prefs['include_scores'] %>
        &middot; Score: <%= number_with_precision(@idea.computed_score, precision: 2) %>
      <% end %>
    </p>
  </div>

  <% case @event_type.to_s %>
  <% when "state_changed" %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1rem; margin-bottom: 1.5rem;">
      <span style="color: <%= @theme[:muted] %>; font-size: 0.85rem;">State changed:</span>
      <span style="color: <%= @theme[:text] %>; font-weight: 600; margin-left: 4px;">
        <%= @metadata['old_state']&.humanize %> &rarr; <%= @metadata['new_state']&.humanize %>
      </span>
    </div>
  <% when "score_changed" %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1rem; margin-bottom: 1.5rem;">
      <span style="color: <%= @theme[:muted] %>; font-size: 0.85rem;">Score changed:</span>
      <span style="color: <%= @theme[:text] %>; font-weight: 600; margin-left: 4px;">
        <%= @metadata['old_score'] %> &rarr; <%= @metadata['new_score'] %>
      </span>
    </div>
  <% when "added_to_list" %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1rem; margin-bottom: 1.5rem;">
      <span style="color: <%= @theme[:muted] %>; font-size: 0.85rem;">Added to list:</span>
      <span style="color: <%= @theme[:text] %>; font-weight: 600; margin-left: 4px;">
        <%= @metadata['list_name'] %>
      </span>
    </div>
  <% when "created" %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1rem; margin-bottom: 1.5rem;">
      <span style="color: <%= @theme[:accent] %>; font-size: 0.85rem;">New idea created</span>
    </div>
  <% end %>

  <% if @metadata['content'].present? && @content_prefs['include_external_content'] %>
    <div style="background: <%= @theme[:card_bg] %>; border-left: 3px solid <%= @theme[:accent] %>; border-radius: 0 6px 6px 0; padding: 1rem; margin-bottom: 1.5rem; color: <%= @theme[:text] %>; font-size: 0.9rem; line-height: 1.6;">
      <p style="margin: 0 0 4px; font-size: 0.75rem; color: <%= @theme[:muted] %>; text-transform: uppercase;">External Content</p>
      <%= simple_format(@metadata['content']) %>
    </div>
  <% end %>

  <% if @idea.description.present? && @content_prefs['include_description'] %>
    <div style="background: <%= @theme[:card_bg] %>; border: 1px solid <%= @theme[:border] %>; border-radius: 6px; padding: 1.25rem; margin-bottom: 1.5rem; color: <%= @theme[:text] %>; line-height: 1.6; font-size: 0.95rem;">
      <%= @idea.description %>
    </div>
  <% end %>

  <% if @content_prefs['include_scores'] %>
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 1.5rem;">
      <tr>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">TRL</td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.trl || 0 %></td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Opportunity</td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.opportunity || 0 %></td>
      </tr>
      <tr>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Timing</td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.timing || 0 %></td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:muted] %>; font-size: 0.85rem;">Difficulty</td>
        <td style="padding: 8px 12px; border: 1px solid <%= @theme[:border] %>; background: <%= @theme[:card_bg] %>; color: <%= @theme[:text] %>; font-weight: 600;"><%= @idea.difficulty || 0 %></td>
      </tr>
    </table>
  <% end %>

  <div style="border-top: 1px solid <%= @theme[:border] %>; padding-top: 1rem; font-size: 0.8rem; color: <%= @theme[:muted] %>;">
    <%= Time.current.strftime("%B %d, %Y at %I:%M %p") %>
  </div>
</div>
```

**Step 2: Commit**

```bash
git add app/views/idea_mailer/event_notification.html.erb
git commit -m "feat: wire theme colors into event_notification email template"
```

---

### Task 8: Run full test suite

**Step 1: Run all tests**

Run: `bin/rails test`
Expected: All green

**Step 2: Final commit if any fixups needed**

```bash
git add -A && git commit -m "fix: address test failures from theme integration"
```
