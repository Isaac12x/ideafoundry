# Build Next Backlog — Design

## Purpose
Global app-wide backlog of "what to build next" items. Lightweight jot-down items, not full ideas.

## Data Model
**`build_items` table:**
- `user_id` (references users)
- `title` (string, required)
- `description` (text, optional)
- `position` (integer, drag-drop ordering)
- `completed` (boolean, default false)
- `completed_at` (datetime, set on completion)
- `timestamps`

## UI
- Nav pill "Build Next" in header nav
- Route: `/build_items`
- Inline add form at top (title + optional description)
- Drag-drop sortable list (native HTML5 drag, same pattern as lists)
- Each item: title, truncated description, drag handle, done checkbox, edit/delete
- "Show completed" toggle at bottom — reveals completed items with slide-down animation
- Completed items: grayed out, strikethrough, not draggable

## Interactions
- Add: Turbo Stream append
- Reorder: PATCH position update via drag controller
- Mark done: checkbox → Turbo Stream move to completed section
- Edit: inline
- Delete: confirm + destroy
- Show/hide completed: Stimulus toggle with CSS transition

## Styling
- Dark forge theme, CSS variables
- Simpler cards than idea-card
- Completed: `opacity: 0.5`, `line-through`, `var(--text-muted)`
