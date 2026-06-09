# App Upgrade Path — Design Spec

**Date:** 2026-05-23  
**Repo:** https://github.com/isaac12x/ideafoundry

## Overview

When a new GitHub release is published on the app's own repo, the user sees a 5-minute toast on any page, followed by a persistent colored upgrade bar on `/settings`. An upgrade button pulls the latest code, migrates the DB, recompiles assets, and restarts the app automatically via the LaunchAgent KeepAlive mechanism.

---

## 1. Data Model

No new DB table. Upgrade state is stored in the existing `user.settings` JSON under the `upgrade` key:

```json
{
  "upgrade": {
    "latest_version": "v1.5.0",
    "release_url": "https://github.com/isaac12x/ideafoundry/releases/tag/v1.5.0",
    "release_body": "First line of release notes…",
    "is_security": false,
    "severity": "green",
    "versions_behind": { "major": 0, "minor": 1, "patch": 0 },
    "checked_at": "2026-05-23T10:00:00Z"
  }
}
```

`severity` is one of `"green"`, `"yellow"`, `"red"`:

| Condition | Severity |
|-----------|----------|
| Any release body contains `CVE`, `vuln`, `vulnerability`, `exploit`, `security fix`, `security patch` (case-insensitive) | `red` |
| 10+ patch versions behind, OR 4+ minor versions behind, OR any major version jump | `yellow` |
| Everything else | `green` |

Current app version is determined once at boot:
```ruby
# config/initializers/app_version.rb
Rails.application.config.app_version = `git describe --tags --abbrev=0`.strip
```

---

## 2. Background Job — `CheckAppUpgradeJob`

- Calls `GET https://api.github.com/repos/isaac12x/ideafoundry/releases/latest`
- Uses the user's stored GitHub token if present; falls back to unauthenticated (60 req/hr limit — fine for hourly checks)
- Computes semver distance between `app_version` and `tag_name`
- Writes result to `user.settings['upgrade']` on the single User record (`User.first`)
- Scheduled hourly in `config/recurring.yml`

No-op if the fetched `tag_name` matches current version.

---

## 3. Toast Notification

**Server side:** `ApplicationController` sets `@upgrade_info` via `before_action :set_upgrade_info`. Returns `nil` if no newer version. The layout renders a `<div data-controller="upgrade-toast">` with release data attributes when `@upgrade_info` is present.

**Client side (`upgrade_toast_controller.js`):**

- On `connect()`, reads `localStorage.upgrade_toast_first_seen_<version>`
- If absent: sets it to `Date.now()`, shows toast
- If present and age < 300,000 ms: shows toast, schedules `setTimeout` to hide after remaining time
- If present and age ≥ 300,000 ms: does nothing (bar takes over)
- If `localStorage.upgrade_toast_dismissed_<version>` is set: does nothing

**Dismiss button (×):** sets `dismissed_<version>` key in localStorage, hides toast immediately.

**Upgrade link in toast:** navigates to `/settings#upgrade` (scrolls to the bar).

Toast is version-keyed so a new release clears old dismissal state automatically.

---

## 4. Settings Upgrade Bar

Partial: `app/views/settings/_upgrade_bar.html.erb`

Rendered at the top of all settings views via `settings/index.html.erb` and each settings sub-page (injected into the settings layout or via a shared include in each template).

**Structure:**
```
[ ↑ icon ]  Update available: v1.5.0 — "First line of release notes"    [ Upgrade ]
```

**CSS classes:**
- `.upgrade-bar--green` — green background
- `.upgrade-bar--yellow` — amber/yellow background  
- `.upgrade-bar--red` — red background

Bar is hidden when `current_version == latest_version` (i.e., post-upgrade, the next job run clears the state).

---

## 5. Upgrade Action

### Routes
```
POST /upgrade          → upgrades#create
GET  /upgrade/status   → upgrades#status
```

### `UpgradesController#create`

Spawns a background thread (not SolidQueue — the queue goes down during restart):

1. `git fetch origin && git reset --hard origin/master`
2. `bundle install` (with `BUNDLE_WITHOUT=development:test`)
3. `bin/rails assets:precompile RAILS_ENV=production`
4. `bin/rails db:migrate RAILS_ENV=production`
5. `kill -TERM $(cat tmp/pids/server.pid)` — LaunchAgent KeepAlive restarts the full stack

Responds immediately: `202 { status: "upgrading" }`.

### `UpgradesController#status`

Returns `200 { status: "upgrading" }` while the process is running. Once Puma is killed, this endpoint stops responding — the client switches to polling `/up`.

### Client (`upgrade_button_controller.js` Stimulus controller)

1. User clicks "Upgrade" button
2. POST to `/upgrade`, button becomes disabled spinner "Upgrading…"
3. Poll `/upgrade/status` every 3s; when it stops responding (network error), switch to polling `/up` every 3s
4. When `/up` returns 200, redirect to `/settings?upgraded=1`
5. Settings page shows a green flash notice on `?upgraded=1`

### Security

`UpgradesController` inherits from `ApplicationController`. No additional auth required — same typing-lock protection as all other pages.

---

## 6. Version Comparison Logic

```ruby
# lib/semver_compare.rb
module SemverCompare
  def self.parse(tag)
    tag.gsub(/^v/, '').split('.').map(&:to_i)
  end

  def self.distance(current, latest)
    c = parse(current)
    l = parse(latest)
    { major: l[0] - c[0], minor: l[1] - c[1], patch: l[2] - c[2] }
  end

  def self.severity(current, latest, release_body)
    return "red" if security_release?(release_body)
    d = distance(current, latest)
    return "yellow" if d[:major] > 0 || d[:minor] >= 4 || d[:patch] >= 10
    "green"
  end

  SECURITY_KEYWORDS = %w[CVE vuln vulnerability exploit security].freeze

  def self.security_release?(body)
    return false if body.blank?
    SECURITY_KEYWORDS.any? { |kw| body.match?(/#{kw}/i) }
  end
end
```

---

## 7. Files Touched / Created

| File | Change |
|------|--------|
| `config/initializers/app_version.rb` | New — reads git tag at boot |
| `config/recurring.yml` | Add hourly `CheckAppUpgradeJob` entry |
| `app/jobs/check_app_upgrade_job.rb` | New |
| `lib/semver_compare.rb` | New |
| `app/controllers/application_controller.rb` | Add `set_upgrade_info` before_action |
| `app/controllers/upgrades_controller.rb` | New |
| `config/routes.rb` | Add upgrade routes |
| `app/views/layouts/application.html.erb` | Add toast partial |
| `app/views/upgrades/_toast.html.erb` | New |
| `app/views/settings/_upgrade_bar.html.erb` | New |
| `app/views/settings/index.html.erb` + sub-pages | Render upgrade bar partial |
| `app/javascript/controllers/upgrade_toast_controller.js` | New |
| `app/javascript/controllers/upgrade_button_controller.js` | New |
| `app/assets/stylesheets/application.css` | Toast + bar styles |
| `app/javascript/controllers/index.js` | Register new controllers |
