# Back-of-the-Napkin Calculations per Idea

Optional spreadsheet-style section in idea create/edit form. Excel-like grid with formulas, cell references, and basic formatting. Persisted per-idea, displayed on show page.

## Scope

**In:** numeric/text/formula cells, A1-style references, arithmetic + IF/SUM/AVG/MIN/MAX/COUNT/ROUND/ABS, %, comparisons, per-cell formatting (bold/number/currency/percent), resizable grid (default 10×5), single sheet per idea.

**Out (v1):** multi-sheet tabs, charts, VLOOKUP/text/date funcs, named ranges, cell styling beyond fmt list, copy-paste from Excel, undo/redo beyond browser default, mobile-optimized editing, "Clear all" toolbar button.

## UX

### Form (create/edit)

- New collapsible panel in main column, after Custom Fields, before Drawings:
  - Title: "Back-of-the-napkin"
  - Collapsed by default; chevron toggle expands.
  - When expanded shows the grid + toolbar.
- Persisted as `napkin_calculations` JSON on idea (`nil` when never opened/touched).
- Empty default grid = 10 rows × 5 cols; "+ Row" / "+ Col" / row/col context-menu delete.

### Grid editor

- Column headers `A B C D E…`, row headers `1 2 3…`.
- Click cell → edit mode (input shows `raw`); blur/Enter commits; Esc cancels.
- Tab/Shift-Tab/Arrow-keys navigate.
- Display rules:
  - `=…` → formula, show computed result (red `#ERR` on parse/eval failure).
  - Numeric string → right-aligned, formatted per `fmt`.
  - Else → text, left-aligned.
- **Selection:** click for single cell; click+drag or Shift+click/Shift+arrow for range. Multi-cell selection highlighted with accent border.
- Toolbar (above grid): format dropdown (auto/number/currency/percent), decimals stepper, bold toggle. Applies to current selection (single cell or range).
- Formula bar (above grid): shows raw of focused cell; editing here mirrors cell input.

### Show page

- Read-only render of the same grid (no toolbar, no formula bar) inside its own panel "Back-of-the-napkin", only rendered if `napkin_calculations` present and non-empty.

## Data Model

### Migration

```ruby
add_column :ideas, :napkin_calculations, :json
```

(SQLite — JSON type, not JSONB.)

### Shape

```json
{
  "rows": 10,
  "cols": 5,
  "cells": {
    "A1": { "raw": "Users",        "fmt": null },
    "B1": { "raw": "1000",         "fmt": "number:0" },
    "A2": { "raw": "ARPU",         "fmt": null },
    "B2": { "raw": "50",           "fmt": "currency:USD:2" },
    "A3": { "raw": "Revenue",      "fmt": "bold" },
    "B3": { "raw": "=B1*B2",       "fmt": "currency:USD:0" }
  }
}
```

- Sparse map: only populated cells stored.
- `raw`: original user input (string). Always.
- `fmt`: `null` | `"bold"` | `"number:<dec>"` | `"currency:<code>:<dec>"` | `"percent:<dec>"`. Bold can stack: `"bold|currency:USD:0"` (pipe-joined).
- Computed values NOT persisted — recomputed on render.

### Idea model

- `serialize :napkin_calculations, coder: JSON` (mirroring `metadata`).
- Helpers:
  - `napkin_present?` → truthy if hash present and `cells` non-empty.
  - `napkin_cell(ref)` → `{raw, fmt}` or nil.

## Formula Engine

- Library (edit-side, JS): **`hyperformula`** (GPL-v3 / commercial; we use the GPL-v3 license key — acceptable since this is a self-hosted private app). Actively maintained, ~500KB, full Excel-compatible engine with 380+ functions. Lazy-loaded — dynamic `import()` triggered on first panel expand, not in main bundle.
- Library (show-side, Ruby): **`dentaku`** gem. Server-side eval, no JS shipped to show page.
- Functions enabled (v1): `SUM AVG MIN MAX COUNT IF ROUND ABS` + arithmetic + comparison operators. Parser exposes more; we don't restrict them but don't document them either.
- Cell-ref resolution: parser callback maps `A1` → cell value (recursing if formula). Cycle detection via visit-set; cycle → `#CYCLE` error.
- Eval errors render as `#ERR` (parse), `#CYCLE`, `#REF` (out-of-range), `#DIV/0`.

## Implementation

### Files

**New:**
- `db/migrate/20260430XXXXXX_add_napkin_calculations_to_ideas.rb`
- `app/javascript/controllers/napkin_controller.js` — Stimulus, owns grid state + render + edit + formula eval.
- `app/views/ideas/_napkin.html.erb` — partial; renders panel shell + hidden field for JSON + initial-state script tag.
- `app/views/ideas/_napkin_readonly.html.erb` — show-page partial, server-rendered table from JSON (no JS needed for view-only).
- `app/assets/stylesheets/napkin.css` — grid styles.
- `app/helpers/napkin_helper.rb` — server-side cell formatter (mirrors JS fmt logic) for read-only render.

**Modified:**
- `db/schema.rb` (migration output)
- `Gemfile` — add `dentaku`.
- `app/models/idea.rb` — `serialize :napkin_calculations`, helper methods.
- `app/controllers/ideas_controller.rb` — permit `:napkin_calculations` param (string of JSON; parsed before save).
- `app/views/ideas/_form.html.erb` — render `_napkin` partial in main column after Custom Fields.
- `app/views/ideas/show.html.erb` — render `_napkin_readonly` if `idea.napkin_present?`.
- `package.json` — add `hot-formula-parser`.

### Stimulus controller (`napkin_controller.js`)

- **Values**: `initial` (JSON string), `inputName` (form param key).
- **Targets**: `grid`, `formulaBar`, `formatSelect`, `decimalsInput`, `boldBtn`, `hiddenInput`, `addRowBtn`, `addColBtn`.
- **State** (in-memory): `{rows, cols, cells: Map<ref, {raw, fmt}>, selection: {anchor, focus}}`.
- **Lazy load:** parser imported on first panel expand: `const { Parser } = await import('hot-formula-parser')`. Loading spinner in panel until ready.
- **Methods**:
  - `connect()` — parse `initial`, render grid skeleton; do NOT load parser yet.
  - `expand()` — lazy-load parser, then render computed cells.
  - `editCell(e)` — swap cell to `<input>` with current `raw`, focus.
  - `commitCell()` — write to state, recompute affected, re-render dirty cells, update hidden input.
  - `evaluate(ref, visited)` — uses `hot-formula-parser`; returns `{value, error}`.
  - `formatCell(ref)` — apply `fmt` to display string.
  - `addRow() / addCol() / removeRow(n) / removeCol(c)`.
  - `selectRange(start, end)` — update selection state, re-highlight.
  - `applyFormat(e)` — to all cells in current selection.
  - `serialize()` — to JSON, write to hidden input on every change (so form submit picks up latest).
- Keyboard: `Tab/Enter/Arrow` navigation, `Shift+Arrow` extend selection, `Esc` cancel edit, `Delete` clears selected cells.

### Server-side render (read-only)

- Show page evaluates formulas server-side via **`dentaku`** gem (MIT, ~50KB gem, pure Ruby, handles arithmetic + IF/SUM/AVG/MIN/MAX/COUNT/ROUND/ABS + comparisons — exactly our v1 function set).
- No JS bundle loaded on show page. Cells pre-rendered to formatted final values in HTML.
- `NapkinHelper`:
  - `napkin_evaluate(data)` → returns `{ref => {display, error}}` map. Uses Dentaku::Calculator with cells fed in dependency order (or via Dentaku's built-in dependency resolver).
  - `format_napkin_cell(raw, fmt, value)` → display string respecting `fmt`.
- Drift risk between `hot-formula-parser` (edit) and `dentaku` (show): low for the v1 function set; both follow Excel semantics on these. Add system test to compare a few representative formulas across both.

### Controller param handling

- `params[:idea][:napkin_calculations]` arrives as JSON string.
- `before_action` parses to hash (or `nil` if blank/invalid).
- Validation: cap `rows ≤ 100`, `cols ≤ 26`, `cells.size ≤ 2000`. Reject if exceeded with form error.

## Testing

- Model: `napkin_present?` truth table, JSON round-trip.
- Controller: param parsing, size limits, persistence on update.
- System test: open form → expand panel → enter labels + formula → save → reload → values persist → show page renders computed result.
- JS unit test (if existing harness supports): formula eval for `=B1*B2`, cycle detection, `#ERR` on bad input.

## Risks

1. **Engine drift** between `hyperformula` (JS, edit) and `dentaku` (Ruby, show). Mitigation: parity tests across the v1 function set; document any Excel-edge-case mismatches if found.
2. **Migration** — `:json` column on SQLite. Existing rows get `nil`. No backfill.
3. **Bundle size** — mitigated by lazy-loading parser on panel expand.
4. **No Excel paste in v1** — acknowledged; deferred.

## Unresolved Questions

None — all questions resolved.
