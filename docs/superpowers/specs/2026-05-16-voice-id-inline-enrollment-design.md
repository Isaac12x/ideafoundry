# Voice ID Inline Enrollment

**Date:** 2026-05-16
**Branch:** fix/security/voice-id

## Problem

Enabling the Voice ID toggle on Settings > Security saves successfully but never redirects the user to record a fingerprint. The separate enrollment page (`typing-lock/voice-id/enroll`) is the wrong surface — enrollment should be part of the security settings form itself.

## Goal

When a user turns on the Voice ID toggle, an inline recording section appears on the same page. The user records the required samples and saves everything in one form submission. No redirect, no separate page.

## Unlock Flow (unchanged)

The unlock flow (`typing_locks#verify_voice`, `typing_locks/voice.html.erb`, `VoiceFingerprint.match?`) is correct and stays as-is. This spec only covers enrollment.

---

## Design

### Settings page (`settings/security.html.erb`)

- The Voice ID toggle is already present.
- Immediately below it, add a hidden `<div class="voice-id-enrollment-inline">` that is revealed when:
  - The toggle is checked AND no fingerprint is stored, OR
  - The user clicks a "Re-record" button (when fingerprint already exists).
- The inline section contains:
  - The canonical phrase displayed prominently.
  - A record button (reuses `voice_id_controller` in `:enroll` mode).
  - Hidden fields: `voice_id_samples[][transcript]`, `voice_id_samples[][duration_ms]`, `voice_id_samples[][rms]` — same shape as the old enrollment form.
  - A sample-count indicator (e.g., "0 / 3 recorded").
- The aside status section retains the "Voice ID" row, simplified to show "Stored (N samples)" or "Not set up."
- The old "Set Up Voice ID" and "Redo Voice ID" links are removed; re-recording is handled by a "Re-record" button that reveals the inline section.

### JS / Stimulus

Extend `voice_id_controller.js`:
- Add a `toggle` action connected to the voice_id checkbox `change` event.
- On check: reveal the inline enrollment section, reset sample index to 0.
- On uncheck: hide the section, clear sample fields.
- Add a `reenroll` action for the "Re-record" button.
- All recording logic (existing `record()`, `storeEnrollmentSample()`) is unchanged.

### Controller (`settings_controller.rb#update_security`)

Remove the existing redirect to `enroll_voice_id_path` and the `was_voice_id_configured` variable entirely. Replace with inline fingerprint handling:

After the existing settings updates, add voice ID fingerprint handling:

```
if voice_id enabled:
  if samples present in params:
    fingerprint = VoiceFingerprint.build(samples: voice_id_sample_params)
    if fingerprint valid (sample_count >= 3):
      user.store_voice_id_fingerprint!(fingerprint)
    else:
      validation error — "Record the phrase 3 times before saving."
  elsif user.voice_id_configured?:
    # keep existing fingerprint — no-op
  else:
    validation error — "Record the Voice ID phrase before saving."
```

`voice_id_params` updated to also permit `voice_id_samples` array.

### Model (`user.rb`)

`update_voice_id_settings` stays responsible for the enabled flag only. Fingerprint storage uses the existing `store_voice_id_fingerprint!`. No model changes needed — controller orchestrates.

### `application_controller.rb`

The unenrolled guard currently redirects to `enroll_voice_id_path`. Change to `settings_security_path`:

```ruby
elsif @user.voice_id_requested? && !@user.voice_id_configured?
  redirect_for_typing_lock(settings_security_path)
```

### Routes

Remove:
- `get  'typing-lock/voice-id/enroll'` → `typing_locks#enroll_voice`
- `post 'typing-lock/voice-id/enroll'` → `typing_locks#create_voice`

### `typing_locks_controller.rb`

Remove `enroll_voice` and `create_voice` actions.

### Views to remove

- `app/views/typing_locks/enroll_voice.html.erb`

### Views to keep / update

- `app/views/typing_locks/_voice_panel.html.erb` — the enroll-mode branch references `voice_id_enrollment_path` (removed route). Strip the enroll-mode branch from the partial; only the unlock-mode branch is needed going forward.
- `app/views/typing_locks/voice.html.erb` — unchanged.

---

## Validation Rules

| State | Voice ID toggle | Samples in params | Existing fingerprint | Result |
|---|---|---|---|---|
| First enable | ON | 3 valid | — | Store fingerprint, save enabled |
| First enable | ON | < 3 valid | — | Error: record all 3 samples |
| First enable | ON | none | — | Error: record before saving |
| Re-record | ON | 3 valid | yes | Replace fingerprint |
| Re-record | ON | none | yes | Keep existing fingerprint |
| Disable | OFF | any | any | Clear fingerprint, save disabled |
| No change | ON | none | yes | Keep fingerprint, save |

---

## What Is Not Changing

- `VoiceFingerprint` model (phrase, matching, fingerprint shape)
- `typing_locks#verify_voice` and the unlock UI
- Session management / challenge tokens
- The canonical phrase: "By my will and power you will open. Open sesame"
