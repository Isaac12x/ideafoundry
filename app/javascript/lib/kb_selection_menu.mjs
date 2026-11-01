// Pure helpers for the KB selection context menu (kb_selection_menu_controller.js).

const MAX_QUOTE = 4000

// Prompt text for the Ask Agent box. "expand" is sent as-is; "ask" leaves the question open for the user.
export function selectionPrompt(mode, text, file) {
  const quote = String(text).trim().slice(0, MAX_QUOTE).split("\n").map((line) => `> ${line}`).join("\n")
  const source = file ? ` (from ${file})` : ""
  const ask = mode === "expand"
    ? `Expand on this passage${source}: explain it in more depth, add useful detail and examples.`
    : `About this passage${source}:`
  return `${ask}\n\n${quote}\n\n`
}

// Top-left for a menu of size w x h opened at (x, y), kept inside the viewport.
export function clampMenu(x, y, w, h, vw, vh, margin = 8) {
  return {
    left: Math.max(margin, Math.min(x, vw - w - margin)),
    top: Math.max(margin, Math.min(y, vh - h - margin))
  }
}

// Next focus index for ArrowUp/Down/Home/End over `count` items, wrapping.
export function nextIndex(key, current, count) {
  if (key === "Home") return 0
  if (key === "End") return count - 1
  return (current + (key === "ArrowDown" ? 1 : -1) + count) % count
}

// Selected text of a textarea, or "" when collapsed.
export function fieldSelection(field) {
  return field.value.slice(field.selectionStart, field.selectionEnd)
}

// Textarea value after inserting the selection as a blockquote right after it; returns { value, caret }.
export function quoteAfterSelection(value, start, end) {
  const quote = value.slice(start, end).trim().split("\n").map((line) => `> ${line}`).join("\n")
  const insert = `\n\n${quote}\n`
  return { value: value.slice(0, end) + insert + value.slice(end), caret: end + insert.length }
}
