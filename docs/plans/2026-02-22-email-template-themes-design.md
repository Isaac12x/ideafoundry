# Email Template Themes Design

## Summary

Add 5 selectable visual themes for share + notification emails. Theme = color palette applied to shared HTML structure. Selected in /settings/email, stored in user settings JSON.

## Themes

| Name | BG | Text | Accent | Card BG | Border | Muted |
|------|-----|------|--------|---------|--------|-------|
| dark | #14141a | #ece8e1 | #d4953a | #1c1c24 | #2a2a36 | #9a9498 |
| light | #ffffff | #1a1a2e | #2563eb | #f8f9fa | #e2e8f0 | #64748b |
| minimal | #ffffff | #333333 | #333333 | transparent | #eeeeee | #888888 |
| bold | #0f0f1a | #f0f0f0 | #ff6b35 | #1a1a2e | #2d2d44 | #a0a0b0 |
| corporate | #f5f5f5 | #2c3e50 | #1a5276 | #ffffff | #d5d8dc | #7f8c8d |

## Storage

`user.settings['email']['template']` — string key, default `'dark'`.

## Architecture

- `app/helpers/email_theme_helper.rb` — `THEMES` constant hash, `self.theme_for(user)` class method
- Mailer actions set `@theme = EmailThemeHelper.theme_for(@user)`
- ERB templates replace hardcoded hex colors with `@theme[:key]` interpolation
- No DB migration needed

## Files Changed

1. **New:** `app/helpers/email_theme_helper.rb` — theme registry + lookup
2. **Edit:** `app/models/user.rb` — add `'template'` to DEFAULT_EMAIL_SETTINGS + update_email_settings slice
3. **Edit:** `app/controllers/settings_controller.rb` — pass `@available_themes` to email view
4. **Edit:** `app/views/settings/email.html.erb` — theme picker cards (radio buttons styled as color swatch cards)
5. **Edit:** `app/mailers/idea_mailer.rb` — set `@theme` in each action
6. **Edit:** `app/views/idea_mailer/share_idea.html.erb` — use `@theme` colors
7. **Edit:** `app/views/idea_mailer/share_list.html.erb` — use `@theme` colors
8. **Edit:** `app/views/idea_mailer/event_notification.html.erb` — use `@theme` colors

## Settings UI

Row of clickable cards in Email Configuration section. Each card: theme name + color swatch circles (bg, accent, text). Selected = gold border. Implemented as radio buttons with CSS styling.

## Scope

- Applies to: share_idea, share_list, event_notification emails
- Does NOT apply to: digest, backup emails (out of scope)
