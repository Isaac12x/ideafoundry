// Pure helpers for the privacy haze that must live outside the lazy gaze bundle (eager controller imports them).
// Honest limits: a browser menu or OS shortcut can still open devtools; this blocks the usual keys, notices docked
// devtools by the window-size heuristic, and (with a lock url) locks the workspace so the DOM is gone. Best effort.

export const DEVTOOLS_GAP = 160 // px: docked devtools shrink inner vs outer window by more than this

// Browser chrome (Arc/Chrome sidebars, side panels) also widens outer-inner, so compare with a baseline taken while clear.
export const windowGap = (w) => ({ w: (w?.outerWidth ?? 0) - (w?.innerWidth ?? 0), h: (w?.outerHeight ?? 0) - (w?.innerHeight ?? 0) })

// current/baseline: { w, h } gaps. Open only when the gap grew by more than `gap` px over the baseline.
export function devtoolsOpen(current, baseline, gap = DEVTOOLS_GAP) {
  if (!current || !baseline) return false
  return current.w - baseline.w > gap || current.h - baseline.h > gap
}

// Keydown event -> true for F12, Ctrl/Cmd+Shift+I/J/C, Cmd+Alt+I/J/C (Alt changes e.key on Mac, so e.code too) and
// Ctrl/Cmd+U (view source).
export function devtoolsKey(e) {
  const k = String(e.key || "").toLowerCase()
  const c = String(e.code || "")
  const letter = (l) => k === l || c === `Key${l.toUpperCase()}`
  const mod = e.ctrlKey || e.metaKey
  if (e.key === "F12" || c === "F12") return true
  if (mod && e.shiftKey && ["i", "j", "c"].some(letter)) return true
  if (e.metaKey && e.altKey && ["i", "j", "c"].some(letter)) return true
  if (mod && !e.shiftKey && !e.altKey && letter("u")) return true
  return false
}
