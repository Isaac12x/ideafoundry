# Voice ID Inline Enrollment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Voice ID enrollment from a separate redirect page to an inline section on Settings > Security, so users record their fingerprint without leaving the page.

**Architecture:** The security settings form gains voice sample hidden fields controlled by a Stimulus `voice-id` controller. `update_security` builds the fingerprint from submitted samples instead of redirecting. The separate `TypingLocksController` enrollment actions and routes are removed.

**Tech Stack:** Rails 7, Stimulus (Hotwire), minitest, `VoiceFingerprint` service object (unchanged), Web Speech API.

---

### Task 1: Write failing tests for new settings controller behavior

**Files:**
- Modify: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Replace the existing "redirects to voice setup" test with a passing-samples test**

In `test/controllers/settings_controller_test.rb`, replace the block starting at line ~113:

```ruby
test "PATCH settings/security enabling voice id with valid samples stores fingerprint" do
  patch settings_security_path, params: {
    typing_lock: { enabled: "0", lock_after_minutes: "5" },
    authenticator_app: { enabled: "0" },
    voice_id: { enabled: "1" },
    voice_id_samples: [
      { transcript: "By my will and power you will open. Open sesame", duration_ms: 1900, rms: 0.42 },
      { transcript: "By my will and power, you will open. Open sesame!", duration_ms: 2050, rms: 0.39 },
      { transcript: "By my will and power you will open open sesame", duration_ms: 1980, rms: 0.41 }
    ]
  }

  assert_redirected_to settings_security_path
  @user.reload
  assert @user.voice_id_requested?
  assert @user.voice_id_configured?
  assert_equal 3, @user.voice_id_fingerprint["sample_count"]
end
```

- [ ] **Step 2: Add test for enabling without samples (no fingerprint) → error**

Add after the above test:

```ruby
test "PATCH settings/security enabling voice id without samples renders error" do
  patch settings_security_path, params: {
    typing_lock: { enabled: "0", lock_after_minutes: "5" },
    authenticator_app: { enabled: "0" },
    voice_id: { enabled: "1" }
  }

  assert_response :unprocessable_entity
  assert_select "input[name=?]", "voice_id[enabled]"
  refute @user.reload.voice_id_configured?
end
```

- [ ] **Step 3: Add test for insufficient samples → error**

```ruby
test "PATCH settings/security enabling voice id with insufficient samples renders error" do
  patch settings_security_path, params: {
    typing_lock: { enabled: "0", lock_after_minutes: "5" },
    authenticator_app: { enabled: "0" },
    voice_id: { enabled: "1" },
    voice_id_samples: [
      { transcript: "By my will and power you will open. Open sesame", duration_ms: 1900, rms: 0.42 }
    ]
  }

  assert_response :unprocessable_entity
  refute @user.reload.voice_id_configured?
end
```

- [ ] **Step 4: Add test for existing fingerprint + empty-transcript samples (browser submits hidden fields with empty values) → keeps fingerprint**

This specifically tests the blank-transcript filter in `voice_id_samples_from_params`.

```ruby
test "PATCH settings/security with existing voice id fingerprint and blank samples keeps fingerprint" do
  samples = [
    { "transcript" => "By my will and power you will open. Open sesame", "duration_ms" => 1900, "rms" => 0.42 },
    { "transcript" => "By my will and power, you will open. Open sesame!", "duration_ms" => 2050, "rms" => 0.39 },
    { "transcript" => "By my will and power you will open open sesame", "duration_ms" => 1980, "rms" => 0.41 }
  ]
  @user.store_voice_id_fingerprint!(VoiceFingerprint.build(samples: samples))
  original_fingerprint = @user.reload.voice_id_fingerprint

  # Simulate browser submitting the 3 hidden fields with empty values (enrollment section was hidden)
  patch settings_security_path, params: {
    typing_lock: { enabled: "0", lock_after_minutes: "5" },
    authenticator_app: { enabled: "0" },
    voice_id: { enabled: "1" },
    voice_id_samples: [
      { transcript: "", duration_ms: "", rms: "" },
      { transcript: "", duration_ms: "", rms: "" },
      { transcript: "", duration_ms: "", rms: "" }
    ]
  }

  assert_redirected_to settings_security_path
  assert_equal original_fingerprint, @user.reload.voice_id_fingerprint
end
```

- [ ] **Step 5: Update the "renders redo actions" test to use a button instead of a link**

Replace the existing `test "GET settings/security renders redo actions on each fingerprint row"` block with:

```ruby
test "GET settings/security renders redo actions on each fingerprint row" do
  original_settings = @user.settings.deep_dup
  @user.update!(settings: {
    "typing_lock" => {
      "enabled" => false,
      "fingerprint" => { "sample_count" => 3, "features" => {} }
    },
    "voice_id" => {
      "enabled" => true,
      "fingerprint" => { "sample_count" => 3, "average_duration_ms" => 2000, "duration_tolerance_ms" => 1200 }
    }
  })

  get settings_security_path

  assert_response :success
  assert_select ".security-fingerprint-row--typing" do
    assert_select "a[href=?]", enroll_typing_lock_path(return_to: settings_security_path), text: "Redo Typing Fingerprint", count: 1
  end
  assert_select "button[data-action=?]", "click->voice-id#showEnrollment", count: 1
ensure
  @user.update!(settings: original_settings) if defined?(original_settings)
end
```

- [ ] **Step 6: Run the settings controller tests to see new tests fail**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: several failures — the new passing-samples test fails (no fingerprint stored), error tests fail (no unprocessable_entity response), "renders redo actions" test fails (still references `enroll_voice_id_path`).

---

### Task 2: Remove enrollment test and typing_locks enrollment tests

**Files:**
- Modify: `test/controllers/typing_locks_controller_test.rb`

- [ ] **Step 1: Delete the "voice id enrollment stores fingerprint" test**

Remove the entire test block (approximately lines 334–350):

```ruby
test "voice id enrollment stores fingerprint after multiple phrase variants" do
  @user.update!(settings: { "voice_id" => { "enabled" => true } })

  post voice_id_enrollment_path, params: {
    voice_id_samples: [...],
    return_to: ideas_path
  }

  assert_redirected_to ideas_path
  assert @user.reload.voice_id_configured?
  assert_equal 3, @user.voice_id_fingerprint["sample_count"]
end
```

- [ ] **Step 2: Run typing_locks controller tests to verify remaining tests still pass**

```bash
bin/rails test test/controllers/typing_locks_controller_test.rb
```

Expected: all remaining tests pass (verify_voice, unlock chain, etc. are unchanged).

---

### Task 3: Remove enrollment infrastructure

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/typing_locks_controller.rb`
- Modify: `app/controllers/application_controller.rb`
- Delete: `app/views/typing_locks/enroll_voice.html.erb`

- [ ] **Step 1: Remove enrollment routes from `config/routes.rb`**

Remove these two lines (around line 155–156):

```ruby
get  'typing-lock/voice-id/enroll', to: 'typing_locks#enroll_voice', as: :enroll_voice_id
post 'typing-lock/voice-id/enroll', to: 'typing_locks#create_voice', as: :voice_id_enrollment
```

- [ ] **Step 2: Remove `enroll_voice`, `create_voice`, and `voice_id_samples` from `typing_locks_controller.rb`**

Remove the `enroll_voice` action (around lines 79–83):
```ruby
def enroll_voice
  @return_to = return_to_path
  @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
  @voice_id_variants = VoiceFingerprint::SETUP_VARIANTS
end
```

Remove the `create_voice` action (around lines 85–99):
```ruby
def create_voice
  @return_to = return_to_path
  fingerprint = VoiceFingerprint.build(samples: voice_id_samples)

  if fingerprint["sample_count"].to_i >= VoiceFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT
    @user.store_voice_id_fingerprint!(fingerprint)
    unlock_typing_session! unless @user.typing_lock_enabled? || @user.authenticator_app_enabled?
    redirect_to @return_to
  else
    @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
    @voice_id_variants = VoiceFingerprint::SETUP_VARIANTS
    flash.now[:alert] = "Say the voice phrase three times before storing Voice ID."
    render :enroll_voice, status: :unprocessable_content
  end
end
```

Remove the `voice_id_samples` private method (around lines 148–156):
```ruby
def voice_id_samples
  raw_samples = params[:voice_id_samples]
  raw_samples = JSON.parse(raw_samples) if raw_samples.is_a?(String)
  Array(raw_samples).map do |sample|
    sample.respond_to?(:to_unsafe_h) ? sample.to_unsafe_h : sample.to_h
  end
rescue JSON::ParserError, NoMethodError
  []
end
```

- [ ] **Step 3: Delete the enrollment view**

```bash
rm app/views/typing_locks/enroll_voice.html.erb
```

- [ ] **Step 4: Update unenrolled guard in `application_controller.rb`**

Find the line (around line 42):
```ruby
redirect_for_typing_lock(enroll_voice_id_path(return_to: target))
```

Replace with:
```ruby
redirect_for_typing_lock(settings_security_path)
```

- [ ] **Step 5: Verify routes and app boot**

```bash
bin/rails routes | grep voice
```

Expected output — only the verify route remains:
```
verify_voice_id_typing_lock  POST  /typing-lock/voice-id  typing_locks#verify_voice
```

---

### Task 4: Extract `load_security_page_vars` and rewrite `update_security`

**Files:**
- Modify: `app/controllers/settings_controller.rb`

- [ ] **Step 1: Extract `load_security_page_vars` private method**

Replace the `security` action body and add the private method. Find the `security` action:

```ruby
def security
  @typing_lock_settings = @user.typing_lock_settings
  @authenticator_app_settings = @user.authenticator_app_settings
  @voice_id_settings = @user.voice_id_settings
  @authenticator_app_qr_svg = AuthenticatorApp.qr_svg(@user.authenticator_app_provisioning_uri) if @user.authenticator_app_configured?
end
```

Replace with:
```ruby
def security
  load_security_page_vars
end
```

In the `private` section, add:
```ruby
def load_security_page_vars
  @typing_lock_settings = @user.typing_lock_settings
  @authenticator_app_settings = @user.authenticator_app_settings
  @voice_id_settings = @user.voice_id_settings
  @authenticator_app_qr_svg = AuthenticatorApp.qr_svg(@user.authenticator_app_provisioning_uri) if @user.authenticator_app_configured?
end

def voice_id_samples_from_params
  raw = params[:voice_id_samples]
  return [] unless raw.present?
  raw = JSON.parse(raw) if raw.is_a?(String)
  Array(raw)
    .map { |s| s.respond_to?(:to_unsafe_h) ? s.to_unsafe_h : s.to_h }
    .reject { |s| s["transcript"].blank? }
rescue JSON::ParserError, NoMethodError
  []
end
```

- [ ] **Step 2: Rewrite `update_security`**

Replace the entire `update_security` method with:

```ruby
def update_security
  typing_lock_updated = @user.update_typing_lock_settings(typing_lock_params)
  authenticator_app_updated = @user.update_authenticator_app_settings(authenticator_app_params)
  voice_id_updated = @user.update_voice_id_settings(voice_id_params)

  unless typing_lock_updated && authenticator_app_updated && voice_id_updated
    load_security_page_vars
    flash.now[:alert] = "Failed to update security settings."
    render :security, status: :unprocessable_content
    return
  end

  if @user.security_lock_enabled?
    unlock_typing_session!
  else
    expire_typing_session!
  end

  if @user.voice_id_requested?
    samples = voice_id_samples_from_params
    if samples.any?
      fingerprint = VoiceFingerprint.build(samples: samples)
      unless fingerprint["sample_count"].to_i >= VoiceFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT
        load_security_page_vars
        flash.now[:alert] = "Record the phrase #{VoiceFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT} times before saving."
        render :security, status: :unprocessable_content
        return
      end
      @user.store_voice_id_fingerprint!(fingerprint)
    elsif !@user.voice_id_configured?
      load_security_page_vars
      flash.now[:alert] = "Record the Voice ID phrase before saving."
      render :security, status: :unprocessable_content
      return
    end
  end

  redirect_to settings_security_path, notice: "Security settings updated."
end
```

- [ ] **Step 3: Confirm the old redirect to `enroll_voice_id_path` and `was_voice_id_configured` are gone**

```bash
grep -n "was_voice_id_configured\|enroll_voice_id_path" app/controllers/settings_controller.rb
```

Expected: no output. The new `update_security` from Step 2 does not contain either.

- [ ] **Step 4: Run the settings controller tests**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: the four new voice_id tests pass. The "renders redo actions" test still fails (view not yet updated). All other tests pass.

---

### Task 5: Strip enroll-mode from `_voice_panel.html.erb`

**Files:**
- Modify: `app/views/typing_locks/_voice_panel.html.erb`

- [ ] **Step 1: Replace the entire partial with the unlock-only version**

Replace the full contents of `app/views/typing_locks/_voice_panel.html.erb` with:

```erb
<% phrase = local_assigns.fetch(:phrase, VoiceFingerprint::CANONICAL_PHRASE) %>
<% return_to = local_assigns[:return_to].presence || root_path %>
<% error = local_assigns[:error] %>
<% opening = local_assigns.fetch(:opening, false) %>
<% redirect_url = local_assigns[:redirect_url].presence || return_to %>

<section class="typing-lock-shell voice-id-shell<%= " voice-id-shell--opening" if opening %>"
         data-controller="voice-id"
         data-voice-id-mode-value="unlock"
         data-voice-id-phrase-value="<%= phrase %>"
         data-voice-id-redirect-url-value="<%= redirect_url %>">
  <div class="typing-lock-topline">
    <span class="typing-lock-mark">Idea Foundry</span>
    <span>Voice ID</span>
  </div>

  <% if opening %>
    <div class="voice-lock-fort voice-lock-fort--opening" aria-live="polite">
      <div class="voice-lock-fort__panel voice-lock-fort__panel--top"></div>
      <div class="voice-lock-fort__panel voice-lock-fort__panel--bottom"></div>
      <div class="voice-lock-fort__lock" aria-label="Unlocked Voice ID lock"></div>
      <div class="voice-lock-fort__reveal">
        <h2>Voice ID matched</h2>
        <p>The fort is opening.</p>
      </div>
    </div>
  <% else %>
    <div class="typing-lock-heading">
      <h2>Voice ID</h2>
      <p>Final lock. Say the exact phrase before the workspace opens.</p>
    </div>

    <blockquote class="voice-id-phrase">"<%= phrase %>"</blockquote>

    <%= form_with url: verify_voice_id_typing_lock_path,
          method: :post,
          local: true,
          class: "voice-id-form",
          data: { turbo: false, voice_id_target: "form" } do %>
      <%= hidden_field_tag :return_to, return_to %>
      <%= hidden_field_tag :voice_payload, "{}", data: { voice_id_target: "payload" } %>
      <%= hidden_field_tag :voice_transcript, "", data: { voice_id_target: "transcript" } %>

      <p class="voice-id-status" data-voice-id-target="status" aria-live="polite">
        Press record and say the phrase.
      </p>

      <% if error.present? %>
        <p class="typing-authenticator-error" role="alert"><%= error %></p>
      <% end %>

      <div class="typing-lock-actions">
        <button type="button" class="btn btn-secondary" data-action="voice-id#record">
          Record phrase
        </button>
        <%= submit_tag "Unlock with Voice ID", class: "btn btn-primary" %>
      </div>

      <p class="typing-lock-noscript">
        If browser speech capture is unavailable, type the transcript manually:
        <%= text_field_tag :voice_transcript, "",
              class: "typing-authenticator-input",
              placeholder: phrase %>
      </p>
    <% end %>
  <% end %>
</section>
```

- [ ] **Step 2: Run the voice unlock tests to verify nothing broke**

```bash
bin/rails test test/controllers/typing_locks_controller_test.rb
```

Expected: all tests pass (voice unlock tests rely on the partial and should still work).

---

### Task 6: Update `settings/security.html.erb` with inline enrollment

**Files:**
- Modify: `app/views/settings/security.html.erb`

- [ ] **Step 1: Replace the voice_id toggle label with the controller-wrapped version**

Find the existing voice_id section (the `hidden_field_tag "voice_id[enabled]"` through the closing `</label>` tag, approximately lines 45–57). Replace the entire block — from the hidden field through and including the closing `</label>` — with this wrapper that adds the inline enrollment section:

```erb
<div data-controller="voice-id" data-voice-id-mode-value="enroll">
  <%= hidden_field_tag "voice_id[enabled]", "0" %>
  <label class="tab-toggle" for="voice_id_enabled">
    <div class="tab-toggle__text">
      <span class="tab-toggle__name">Require Voice ID</span>
      <span class="tab-toggle__description">Say "By my will and power you will open. Open sesame". Voice ID is always the final lock before the workspace opens.</span>
    </div>
    <span class="tab-toggle__switch">
      <%= check_box_tag "voice_id[enabled]", "1", @user.voice_id_requested?,
            id: "voice_id_enabled",
            class: "tab-toggle__input",
            data: { action: "change->voice-id#toggleEnrollment" } %>
      <span class="tab-toggle__track" aria-hidden="true">
        <span class="tab-toggle__thumb"></span>
      </span>
    </span>
  </label>

  <div class="voice-id-enrollment-inline"
       data-voice-id-target="enrollmentSection"
       <%= 'hidden' unless @user.voice_id_requested? && !@user.voice_id_configured? %>>
    <p class="voice-id-enrollment-inline__phrase">"<%= VoiceFingerprint::CANONICAL_PHRASE %>"</p>
    <p class="voice-id-status" data-voice-id-target="status" aria-live="polite">Press Record and say the phrase.</p>
    <% VoiceFingerprint::SETUP_VARIANTS.each_with_index do |variant, i| %>
      <%= hidden_field_tag "voice_id_samples[][transcript]", "",
            data: { voice_id_target: "sampleTranscript", voice_id_variant: variant, voice_id_index: i } %>
      <%= hidden_field_tag "voice_id_samples[][duration_ms]", "",
            data: { voice_id_target: "sampleDuration", voice_id_index: i } %>
      <%= hidden_field_tag "voice_id_samples[][rms]", "",
            data: { voice_id_target: "sampleRms", voice_id_index: i } %>
    <% end %>
    <div class="voice-id-enrollment-inline__actions">
      <button type="button" class="btn btn-secondary btn-sm" data-action="voice-id#record">
        Record next sample
      </button>
    </div>
  </div>

  <% if @user.voice_id_enabled? %>
    <button type="button" class="btn btn-sm" data-action="click->voice-id#showEnrollment">
      Re-record Voice ID
    </button>
  <% end %>
</div>
```

- [ ] **Step 2: Update the aside Voice ID status row**

Find the `security-fingerprint-row--voice` section in the `<aside>` (approximately lines 115–136). Replace the entire section with:

```erb
<section class="security-fingerprint-row security-fingerprint-row--voice">
  <div class="security-fingerprint-row__content">
    <span class="typing-settings-status__label">Voice ID</span>
    <% if @user.voice_id_configured? %>
      <strong><%= @user.voice_id_enabled? ? "Enabled" : "Stored" %></strong>
      <p><%= @user.voice_id_fingerprint["sample_count"] %> derived voice samples are stored in the database. Raw audio is not stored.</p>
    <% else %>
      <strong>Not set up</strong>
      <p>Enable Voice ID and record the phrase to set up.</p>
    <% end %>
  </div>
</section>
```

- [ ] **Step 3: Run settings controller tests to verify the "renders redo actions" test now passes**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: all settings controller tests pass, including "renders redo actions" (now finds the `showEnrollment` button).

- [ ] **Step 4: Commit**

```bash
git add app/views/settings/security.html.erb \
        app/views/typing_locks/_voice_panel.html.erb \
        app/views/typing_locks/enroll_voice.html.erb \
        app/controllers/settings_controller.rb \
        app/controllers/typing_locks_controller.rb \
        app/controllers/application_controller.rb \
        config/routes.rb \
        test/controllers/settings_controller_test.rb \
        test/controllers/typing_locks_controller_test.rb
git commit -m "feat: voice id enrollment inline on security settings page

Removes the separate enrollment page/routes. When the Voice ID toggle
is turned on, an inline recording section appears in the security
settings form. Fingerprint is built from submitted samples in
update_security. Unlock flow unchanged."
```

---

### Task 7: Extend `voice_id_controller.js`

**Files:**
- Modify: `app/javascript/controllers/voice_id_controller.js`

- [ ] **Step 1: Replace the full controller with the extended version**

Replace the entire contents of `app/javascript/controllers/voice_id_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "form",
    "payload",
    "status",
    "transcript",
    "sampleTranscript",
    "sampleDuration",
    "sampleRms",
    "enrollmentSection",
  ];
  static values = {
    mode: String,
    phrase: String,
    redirectUrl: String,
  };

  connect() {
    this.sampleIndex = 0;
    if (this.element.classList.contains("voice-id-shell--opening")) {
      window.setTimeout(() => {
        window.location.assign(this.redirectUrlValue || "/");
      }, 1700);
    }
  }

  toggleEnrollment(event) {
    if (!this.hasEnrollmentSectionTarget) return;
    if (event.target.checked) {
      this.enrollmentSectionTarget.removeAttribute("hidden");
      this.resetEnrollment();
    } else {
      this.enrollmentSectionTarget.setAttribute("hidden", "");
      this.resetEnrollment();
    }
  }

  showEnrollment() {
    if (!this.hasEnrollmentSectionTarget) return;
    this.enrollmentSectionTarget.removeAttribute("hidden");
    this.resetEnrollment();
  }

  resetEnrollment() {
    this.sampleIndex = 0;
    this.sampleTranscriptTargets.forEach((t) => (t.value = ""));
    this.sampleDurationTargets.forEach((t) => (t.value = ""));
    this.sampleRmsTargets.forEach((t) => (t.value = ""));
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Press Record and say the phrase.";
    }
  }

  record() {
    const startedAt = performance.now();
    this.statusTarget.textContent = "Listening… say the phrase now.";

    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Recognition) {
      this.statusTarget.textContent =
        "Speech recognition is unavailable. Type the transcript below, then submit.";
      return;
    }

    const recognition = new Recognition();
    recognition.lang = "en-US";
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event) => {
      const transcript = event.results?.[0]?.[0]?.transcript || "";
      const durationMs = Math.round(performance.now() - startedAt);
      const sample = { transcript, duration_ms: durationMs, rms: 0 };

      if (this.modeValue === "enroll") {
        this.storeEnrollmentSample(sample);
      } else {
        this.transcriptTarget.value = transcript;
        this.payloadTarget.value = JSON.stringify(sample);
        this.statusTarget.textContent = `Captured: "${transcript}"`;
      }
    };

    recognition.onerror = () => {
      this.statusTarget.textContent =
        "Could not capture speech. Try again or type the transcript manually.";
    };

    recognition.start();
  }

  storeEnrollmentSample(sample) {
    const index = Math.min(this.sampleIndex, this.sampleTranscriptTargets.length - 1);
    if (index < 0) return;

    this.sampleTranscriptTargets[index].value = sample.transcript;
    this.sampleDurationTargets[index].value = sample.duration_ms;
    this.sampleRmsTargets[index].value = sample.rms;
    this.sampleIndex = Math.min(index + 1, this.sampleTranscriptTargets.length);

    const total = this.sampleTranscriptTargets.length;
    if (this.sampleIndex >= total) {
      this.statusTarget.textContent = `All ${total} samples recorded — save settings to finish.`;
    } else {
      this.statusTarget.textContent = `${this.sampleIndex} of ${total} recorded. Press Record again.`;
    }
  }
}
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass. If any JS-related system tests exist for voice_id, run them too:

```bash
bin/rails test test/system/ 2>/dev/null || true
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/voice_id_controller.js
git commit -m "feat: extend voice-id controller with toggle/re-enroll actions"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run the complete test suite**

```bash
bin/rails test
```

Expected: all tests pass with no errors or failures.

- [ ] **Step 2: Verify routes no longer include enrollment paths**

```bash
bin/rails routes | grep -E "enroll_voice|voice_id_enrollment"
```

Expected: no output (those routes are gone).

- [ ] **Step 3: Verify only the verify route remains for voice**

```bash
bin/rails routes | grep voice
```

Expected:
```
verify_voice_id_typing_lock  POST  /typing-lock/voice-id  typing_locks#verify_voice
```

- [ ] **Step 4: Confirm no references to removed paths remain in app code**

```bash
grep -r "enroll_voice_id_path\|voice_id_enrollment_path" app/ config/
```

Expected: no output.

---

## Summary of files changed

| File | Change |
|---|---|
| `config/routes.rb` | Remove 2 enrollment routes |
| `app/controllers/typing_locks_controller.rb` | Remove `enroll_voice`, `create_voice`, `voice_id_samples` |
| `app/controllers/settings_controller.rb` | Rewrite `update_security`; add `load_security_page_vars`, `voice_id_samples_from_params` |
| `app/controllers/application_controller.rb` | Guard redirects to `settings_security_path` |
| `app/views/settings/security.html.erb` | Add inline enrollment section + updated aside |
| `app/views/typing_locks/_voice_panel.html.erb` | Strip enroll mode, keep unlock mode |
| `app/javascript/controllers/voice_id_controller.js` | Add `toggleEnrollment`, `showEnrollment`, `resetEnrollment` |
| `test/controllers/settings_controller_test.rb` | Replace old redirect test; add 4 new tests; update redo test |
| `test/controllers/typing_locks_controller_test.rb` | Remove enrollment test |
| **Deleted** | `app/views/typing_locks/enroll_voice.html.erb` |
