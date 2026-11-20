// Palette search history in localStorage: { "<query>": { n: uses, t: last-used ms } }. Every access is guarded.
const KEY = "command_palette_history"
const MAX_ENTRIES = 50 // pruned by the same rank, so rarely-used old queries fall off

const read = (store) => { try { return JSON.parse(store.getItem(KEY)) || {} } catch { return {} } }

// Most used first, ties broken by recency. With <= limit entries this is just "the last N" by use.
export function topSearches(store, limit = 5) {
  return Object.entries(read(store)).sort(([, a], [, b]) => b.n - a.n || b.t - a.t).slice(0, limit).map(([q]) => q)
}

export function recordSearch(store, query, now = Date.now()) {
  const q = query.trim()
  if (!q) return
  const all = read(store)
  all[q] = { n: (all[q]?.n || 0) + 1, t: now }
  const kept = Object.entries(all).sort(([, a], [, b]) => b.n - a.n || b.t - a.t).slice(0, MAX_ENTRIES)
  try { store.setItem(KEY, JSON.stringify(Object.fromEntries(kept))) } catch { /* private mode / quota */ }
}

export function clearSearches(store) {
  try { store.removeItem(KEY) } catch { /* ignore */ }
}
