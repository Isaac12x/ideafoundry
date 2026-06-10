# Display Settings Page — Design Spec

**Date:** 2026-05-19

## Goal

Move the display settings (quote + contrast) out of the settings index page and into a dedicated `/settings/display` sub-page. Replace the contrast dropdown with a continuous drag bar (range slider, 70–150, default 100).

---

## Route & Controller

- Add `GET /settings/display` → `settings#display`
- Add `PATCH /settings/display` → `settings#update_display`, named `settings_display`
- The `update_display` action already exists; update its redirect target from `settings_path` to `settings_display_path`.
- Add a `display` action that assigns `@display_quote` and `@display_contrast`.

---

## Contrast Storage

- `ALLOWED_CONTRAST_VALUES` changes from `%w[normal high]` to accept integer strings in the range 70–150, plus `'normal'` as a fallback alias for 100.
- `display_contrast` returns an integer (default 100). On read, legacy `'high'` maps to 130; legacy `'normal'` maps to 100.
- `update_display_quote` stores the raw integer string after clamping to 70–150.
- The stored key in `user.settings` remains `'display_contrast'`.

---

## CSS

- Remove the `body[data-contrast="high"]` block.
- In `application.html.erb`, set an inline CSS variable on `<body>`: `style="--contrast: <%= (@user&.display_contrast || 100) %>%"`.
- Add one CSS rule: `.app-container { filter: contrast(var(--contrast, 100%)); }` (scoped to avoid compositing issues with fixed/absolute elements outside the container).
- Existing `data-contrast` attribute on body can be kept or removed; it becomes unused for styling.

---

## View — `settings/display.html.erb`

Pattern follows other settings sub-pages (e.g., `settings/lists.html.erb`):

```
Page header: "Display" + back link → settings_path
Form: PATCH settings_display_path

  Quote section:
    label: "Page Quote"
    textarea: display_settings[quote], existing behavior

  Contrast section:
    label: "Contrast" + live numeric readout (e.g. "110%")
    range input: display_settings[contrast], min=70, max=150, step=1, value=@display_contrast
    JS: on input, update readout span + set document.body.style.setProperty('--contrast', value + '%')

  Submit button: "Save Display"
```

Live preview JS is inline or a small Stimulus controller — no server round-trip needed during drag.

---

## Settings Index Changes

- Remove the `display-quote-settings` section (form + surrounding markup).
- Add a `settings-row` link to `settings_display_path` at the top of the `settings-list`, labeled "Display" with description "Quote and contrast settings".

---

## Out of Scope

- Dark/light mode toggle
- Font size or density controls
- Per-page contrast overrides
