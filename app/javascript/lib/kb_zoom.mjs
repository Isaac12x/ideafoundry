// Page zoom (devicePixelRatio vs. the value at load) and pinch zoom (visualViewport.scale) both enlarge CSS
// pixels on screen. Scaling a bar by the inverse keeps its physical size constant.
// Limit: the baseline is the zoom the page was loaded at, so a page opened while zoomed treats that as 100%.
export const baselineDpr = globalThis.devicePixelRatio || 1

export function inverseScale(dpr, baseDpr = baselineDpr, pinch = 1) {
  const zoom = (dpr / baseDpr) * pinch
  return Number.isFinite(zoom) && zoom > 0 ? Math.min(Math.max(1 / zoom, 0.2), 5) : 1
}

export function clock(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00"
  const s = Math.floor(seconds)
  const [h, m] = [Math.floor(s / 3600), Math.floor((s % 3600) / 60)]
  const ss = String(s % 60).padStart(2, "0")
  return h ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`
}
