// Single table of app-provided shortcuts. Strict JSON (User reads it for server validation); keep it parseable.
export const DEFAULT_BINDINGS = {
  "cheatsheet": { "key": "?", "label": "Toggle this cheatsheet" },
  "search": { "key": "Ctrl/Cmd+K", "label": "Search ideas" },
  "hints": { "key": "Ctrl/Cmd+.", "label": "Show action hints" },
  "focus_search": { "key": "/", "label": "Focus search or filters" },
  "save": { "key": "Ctrl/Cmd+S", "label": "Save the current form" },
  "submit": { "key": "Ctrl/Cmd+Enter", "label": "Submit the current form" },
  "ask_agent": { "key": "Ctrl/Cmd+J", "label": "Open Ask Agent" },
  "lock": { "key": "Ctrl/Cmd+L", "label": "Lock workspace" },
  "edit": { "key": "e", "label": "Edit the current item" },
  "prev_tab": { "key": "[", "label": "Previous tab" },
  "next_tab": { "key": "]", "label": "Next tab" },
  "go_plan": { "key": "g p", "label": "Plan" },
  "go_ideas": { "key": "g i", "label": "Ideas" },
  "go_licensing": { "key": "g l", "label": "Licensing" },
  "go_intake": { "key": "g n", "label": "Intake" },
  "go_topologies": { "key": "g t", "label": "Topologies" },
  "go_kb": { "key": "g k", "label": "Knowledge Base" },
  "go_backlog": { "key": "g b", "label": "Backlog" },
  "go_settings": { "key": "g s", "label": "Settings" },
  "new_idea": { "key": "n i", "label": "New idea" },
  "new_list": { "key": "n l", "label": "New named list" },
  "new_topology": { "key": "n t", "label": "New topology" },
  "new_import": { "key": "n s", "label": "Import submissions" }
}

// The user's overrides ({ id: binding }) are serialized onto <body> by the layout.
let cached = { raw: "{}", parsed: {} }
export function overrides() {
  const raw = globalThis.document?.body?.dataset?.shortcutOverrides || "{}"
  if (raw !== cached.raw) {
    try {
      cached = { raw, parsed: JSON.parse(raw) }
    } catch {
      cached = { raw, parsed: {} }
    }
  }
  return cached.parsed
}

export const isMac = () => /Mac|iP(hone|ad|od)/i.test(globalThis.navigator?.userAgentData?.platform || globalThis.navigator?.platform || "")

// Letters the browser/OS owns behind Cmd (Mac) or Ctrl (elsewhere): save, print, lock-screen, tab/window/find...
// Cmd/Ctrl + these must reach the browser untouched, so an app action bound to them moves to Ctrl (Mac) or Alt (elsewhere).
// ponytail: Ctrl+K is kill-line on Mac text fields, but Cmd+K is no browser shortcut there, so K only moves off Windows/Linux.
export const browserReserved = (key) => new RegExp(`^[defghjlmnopqrstuwy${isMac() ? "" : "k"}]$`, "i").test(key)

// "Ctrl/Cmd+S" is the user-facing form; what actually fires is Ctrl+S on Mac, Alt+S elsewhere.
export function platformBinding(bind) {
  const parts = String(bind || "").match(/^Ctrl\/Cmd\+((?:Shift\+)?)(.)$/)
  if (!parts || !browserReserved(parts[2])) return bind
  return `${isMac() ? "Ctrl" : "Alt"}+${parts[1]}${parts[2]}`
}

// Effective binding: the user's if set, else the default.
export function binding(id) {
  return platformBinding(overrides()[id] || DEFAULT_BINDINGS[id]?.key)
}

// The server renders "Ctrl/Cmd+L"; show the key that really fires here. data-shortcut-id = a shortcut's effective
// binding, data-shortcut-raw = a literal binding; data-shortcut-title="Lock" sets the title instead of the text
// (inputs get a placeholder).
export function labelShortcuts(root = document) {
  root.querySelectorAll("[data-shortcut-id], [data-shortcut-raw]").forEach((el) => {
    const text = el.dataset.shortcutId ? binding(el.dataset.shortcutId) : platformBinding(el.dataset.shortcutRaw)
    if (el.dataset.shortcutTitle) el.title = `${el.dataset.shortcutTitle} (${text})`
    else if (el.matches("input")) el.placeholder = text
    else el.textContent = text
  })
}

const codeKey = (code) => String(code || "").replace(/^(Key|Digit)/, "").toLowerCase()

// Single-step binding ("Ctrl/Cmd+Shift+S", "?", "e") vs a keydown event.
export function matches(bind, event) {
  if (!bind || !event.key || bind.includes(" ")) return false

  const parts = bind.match(/^((?:(?:Ctrl\/Cmd|Ctrl|Alt|Shift)\+)*)(.+)$/)
  if (!parts) return false

  const [, mods, rawKey] = parts
  const strictCtrl = mods.includes("Ctrl+")
  const mod = mods.includes("Ctrl/Cmd+") || strictCtrl
  const key = rawKey.toLowerCase()
  const shift = mods.includes("Shift+")
  const chord = mod || mods.includes("Alt+")

  if (strictCtrl ? !event.ctrlKey || event.metaKey : (event.metaKey || event.ctrlKey) !== mod) return false
  if (event.altKey !== mods.includes("Alt+")) return false
  // Shift is implicit for symbols like "?", so only letters/digits/named keys must match it.
  if (shift ? !event.shiftKey : event.shiftKey && /^[a-z0-9]|^.{2,}$/.test(key)) return false

  // Chords also match the physical key, but only when the layout gave no Latin letter/digit
  // (Alt+P yields "π" on macOS; on Colemak Ctrl+R has code KeyS and must not be Save).
  return event.key.toLowerCase() === key || (chord && !/^[a-z0-9]$/i.test(event.key) && codeKey(event.code) === key)
}

// Two-step bindings ("g p"): [first, second] lowercase keys, or null.
export function sequenceKeys(bind) {
  return /^\S \S$/.test(bind || "") ? bind.toLowerCase().split(" ") : null
}
