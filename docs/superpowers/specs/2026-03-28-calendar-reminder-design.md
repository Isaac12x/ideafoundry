# Calendar Reminder per Idea

Add a calendar reminder button to each idea's show page. Users pick a date/time and export as .ics or Google Calendar link with a deeplink back to the idea.

## UI

- Calendar icon button in header action bar (next to Edit/Email/Delete)
- Click opens a popover with:
  - `datetime-local` input, default: 1 week from now at 09:00
  - Two action buttons: "Download .ics" and "Google Calendar"
- Popover closes on outside click or after action

## Event Content

- **Title**: `Review: {idea title}`
- **Description** (plain text, newline-separated):
  - Deeplink: generated via `idea_url(@idea)`
  - Score: `Score: {computed_score}`
  - State: `State: {state}`
  - Snippet: first ~200 chars of description stripped to plain text
- **Alert**: VALARM at event time (TRIGGER:PT0M)
- **Duration**: 30 minutes

## Implementation

### No backend changes

No new models, controllers, routes, or migrations. Everything is client-side.

### Stimulus Controller (`reminder_controller.js`)

- **Values** (from data attributes, rendered server-side):
  - `title` (String) — idea title
  - `url` (String) — `idea_url(@idea)` deeplink
  - `score` (String) — computed score
  - `state` (String) — current state label
  - `snippet` (String) — plain-text description excerpt
- **Targets**: `popover`, `datetime`
- **Actions**:
  - `toggle` — show/hide popover
  - `downloadIcs` — generate .ics blob, trigger download
  - `openGoogle` — open Google Calendar URL in new tab
  - `closeOnOutsideClick` — close popover if click is outside

### .ics Generation (client-side)

Build a VCALENDAR string:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Idea Foundry//Reminder//EN
BEGIN:VEVENT
UID:{random uuid}@ideas.local
DTSTAMP:{now in UTC}
DTSTART:{selected datetime in UTC}
DTEND:{selected datetime + 30min in UTC}
SUMMARY:Review: {title}
DESCRIPTION:{url}\n\nScore: {score}\nState: {state}\n\n{snippet}
BEGIN:VALARM
TRIGGER:PT0M
ACTION:DISPLAY
DESCRIPTION:Review: {title}
END:VALARM
END:VEVENT
END:VCALENDAR
```

Download via `URL.createObjectURL(new Blob([icsContent], { type: 'text/calendar' }))`.

### Google Calendar Link

```
https://calendar.google.com/calendar/render?action=TEMPLATE
  &text=Review: {title}
  &dates={start}/{end}  (YYYYMMDDTHHmmSSZ format)
  &details={url + score + state + snippet, URI-encoded}
```

Open in new tab via `window.open()`.

### View Changes (`ideas/show.html.erb`)

Add reminder button + popover markup in header action bar. Pass idea data as Stimulus values via data attributes on the controller element.

### Styling

Popover styled inline with existing app patterns:
- Absolute positioned below button
- Same border/shadow/radius as existing UI elements
- Responsive: works on narrow viewports

## Files Changed

1. `app/javascript/controllers/reminder_controller.js` — new Stimulus controller
2. `app/views/ideas/show.html.erb` — add button + popover markup in header
3. `app/assets/stylesheets/application.css` — popover styles (minimal)
