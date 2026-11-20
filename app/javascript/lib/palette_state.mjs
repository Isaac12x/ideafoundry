// Pure state machine for the command palette: level 0 = results, level 1 = actions of one item.
// Drilling in remembers the query and highlighted row so going back restores both.
export const MODES = ["quick", "similar", "deep"]

export const initialState = () => ({ level: 0, mode: "quick", saved: null })

// "> lock" -> commands only, filter "lock".
export function parseQuery(raw) {
  const q = String(raw ?? "").trim()
  return q.startsWith(">") ? { commandsOnly: true, text: q.slice(1).trim() } : { commandsOnly: false, text: q }
}

export const canEnter = (state, item) => state.level === 0 && !!item?.actions

export const enter = (state, { query, index, item, groups }) =>
  canEnter(state, item) ? { ...state, level: 1, saved: { query, index, item, groups } } : state

// Returns { state, query, index, groups } to restore, or null when there is nothing to go back to.
export function back(state) {
  if (state.level !== 1 || !state.saved) return null
  const { query, index, groups } = state.saved
  return { state: { ...state, level: 0, saved: null }, query, index, groups }
}

export const setMode = (state, mode) => ({ ...state, mode: MODES.includes(mode) ? mode : state.mode, level: 0, saved: null })

// Server search (similar/deep read files and embeddings) only past this many characters.
export const minChars = (mode) => (mode === "quick" ? 2 : 3)
export const DEBOUNCE_MS = 250

// Server actions carry `label`; palette rows render `title`.
export const actionRows = (item, q = "") =>
  (item.actions || []).filter((a) => a.label.toLowerCase().includes(q.toLowerCase())).map((a) => ({ ...a, title: a.label }))
