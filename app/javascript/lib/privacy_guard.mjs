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

// Haze strength 1 (light veil: faint but shapes visible) .. 10 (near invisible) -> CSS custom properties.
export const DEFAULT_HAZE_STRENGTH = 6
export function hazeVars(strength) {
  const n = Number(strength)
  const s = Math.min(10, Math.max(1, Math.round(Number.isFinite(n) && n > 0 ? n : DEFAULT_HAZE_STRENGTH)))
  const t = (s - 1) / 9
  const r = (x, d = 3) => Number(x.toFixed(d))
  return {
    "--privacy-haze-opacity": String(r(0.45 - 0.42 * t)),
    "--privacy-haze-blur": `${r(4 + 14 * t, 1)}px`,
    "--privacy-haze-saturate": String(r(0.8 - 0.6 * t, 2)),
    "--privacy-haze-scale": String(r(1 - 0.02 * t, 4)),
  }
}

// Nav eye: "off" (feature off / controller absent), "watching" (on, content clear), "hazed".
export const indicatorState = (enabled, hazy) => (!enabled ? "off" : hazy ? "hazed" : "watching")

export function indicatorTitle(state, shortcut) {
  const tail = shortcut ? ` (${shortcut})` : ""
  if (state === "hazed") return `Privacy haze is on. Look at the screen to clear it${tail}`
  if (state === "watching") return `Privacy haze is watching. Turn off${tail}`
  return `Privacy haze is off. Turn on${tail}`
}

export function paintIndicator(el, state, shortcut) {
  if (!el) return
  el.dataset.state = state
  el.title = indicatorTitle(state, shortcut)
  el.setAttribute("aria-label", el.title)
  el.setAttribute("aria-pressed", state === "off" ? "false" : "true")
}
