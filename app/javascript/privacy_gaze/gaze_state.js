// Pure gaze logic (no DOM, no mediapipe): classify a frame as looking/away and debounce the result.

// "Looking" = the features sit inside this device's screen envelope (per-feature min/max over a 5-point calibration:
// centre + four viewport corners) widened by a margin that shrinks as sensitivity (1..10) grows.
// ponytail: MARGIN_AT_5 is the tuning knob; sensitivity scales it (about 2x at 1, 0.4x at 10).
import { FEATURES, DEFAULT_ENVELOPE } from "../lib/gaze_profiles.mjs"
export * from "../lib/gaze_profiles.mjs" // per-screen calibration storage: loadEnvelope / saveEnvelope / profiles
export const MARGIN_AT_5 = { yaw: 12, pitch: 10, h: 0.15, v: 0.2 } // deg / deg / blendshape units
export const DEFAULT_SENSITIVITY = 5
export const DEFAULT_AWAY_MS = 2500
export const DEFAULT_CLEAR_MS = 150
export const MIN_POINT_SAMPLES = 5
// Calibration stage targets, in viewport fractions: centre first, then the corners.
export const CALIBRATION_POINTS = [
  { x: 0.5, y: 0.5 }, { x: 0.08, y: 0.1 }, { x: 0.92, y: 0.1 }, { x: 0.92, y: 0.9 }, { x: 0.08, y: 0.9 },
]

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n))
const deg = (rad) => (rad * 180) / Math.PI
const score = (shapes, name) => shapes?.find((c) => c.categoryName === name)?.score ?? 0

// FaceLandmarker result -> { yaw, pitch, h, v } or null when no face. matrix is column-major 4x4.
export function extractFeatures(result, i = 0) {
  const m = result?.facialTransformationMatrixes?.[i]?.data
  const shapes = result?.faceBlendshapes?.[i]?.categories
  if (!m || !shapes) return null
  const r02 = clamp(m[8], -1, 1), r12 = m[9], r22 = m[10]
  const s = (n) => score(shapes, n)
  return {
    yaw: deg(Math.atan2(r02, r22)),
    pitch: deg(Math.atan2(-r12, Math.hypot(r02, r22))),
    h: (s("eyeLookOutLeft") - s("eyeLookInLeft") + s("eyeLookInRight") - s("eyeLookOutRight")) / 2,
    v: (s("eyeLookUpLeft") + s("eyeLookUpRight") - s("eyeLookDownLeft") - s("eyeLookDownRight")) / 2,
  }
}

// Every face in the frame: features + normalized centre (to pair with Human's faces and tell the owner from others).
export function extractFaces(result) {
  const n = result?.faceLandmarks?.length ?? 0
  const out = []
  for (let i = 0; i < n; i++) {
    const f = extractFeatures(result, i)
    if (!f) continue
    const xs = result.faceLandmarks[i].map((p) => p.x), ys = result.faceLandmarks[i].map((p) => p.y)
    out.push({ ...f, center: { x: (Math.min(...xs) + Math.max(...xs)) / 2, y: (Math.min(...ys) + Math.max(...ys)) / 2 } })
  }
  return out
}

// Margin multiplier vs sensitivity 5: 1 -> ~2.08x (yaw 25deg), 5 -> 1x (12deg), 10 -> ~0.42x (5deg). Monotonic.
export function marginScale(sensitivity = DEFAULT_SENSITIVITY) {
  const s = clamp(Number(sensitivity) || DEFAULT_SENSITIVITY, 1, 10)
  const yaw = s <= 5 ? 25 + (12 - 25) * ((s - 1) / 4) : 12 + (5 - 12) * ((s - 5) / 5)
  return yaw / 12
}
export function margins(sensitivity = DEFAULT_SENSITIVITY) {
  const k = marginScale(sensitivity)
  return Object.fromEntries(FEATURES.map((n) => [n, MARGIN_AT_5[n] * k]))
}

export function isLooking(f, envelope = DEFAULT_ENVELOPE, sensitivity = DEFAULT_SENSITIVITY) {
  if (!f) return false // no face = away
  const env = envelope?.min && envelope?.max ? envelope : DEFAULT_ENVELOPE
  const m = margins(sensitivity)
  return FEATURES.every((k) => f[k] >= env.min[k] - m[k] && f[k] <= env.max[k] + m[k])
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b)
  const i = s.length >> 1
  return s.length % 2 ? s[i] : (s[i - 1] + s[i]) / 2
}

// Median of feature samples for one calibration point; null when there are too few.
export function pointMedian(samples, min = MIN_POINT_SAMPLES) {
  const good = (samples || []).filter(Boolean)
  if (good.length < min) return null
  return Object.fromEntries(FEATURES.map((k) => [k, median(good.map((f) => f[k]))]))
}

// perPoint: one array of feature samples per calibration point (centre first).
// -> { center, min, max } over the per-point medians, or null when any point was not seen.
export function buildEnvelope(perPoint, min = MIN_POINT_SAMPLES) {
  const pts = (perPoint || []).map((s) => pointMedian(s, min))
  if (!pts.length || pts.some((p) => !p)) return null
  const each = (fn) => Object.fromEntries(FEATURES.map((k) => [k, fn(pts.map((p) => p[k]))]))
  return { center: pts[0], min: each((xs) => Math.min(...xs)), max: each((xs) => Math.max(...xs)) }
}

// Starts "away" (fail closed) unless told otherwise. Flips only after the opposite reading has held for the whole delay.
export function createHysteresis({ awayMs = DEFAULT_AWAY_MS, clearMs = DEFAULT_CLEAR_MS, initial = "away" } = {}) {
  let state = initial, since = null
  return {
    get state() { return state },
    reset() { state = "away"; since = null },
    setDelays(a, c) { awayMs = a ?? awayMs; clearMs = c ?? clearMs },
    step(looking, now) {
      const target = looking ? "looking" : "away"
      if (target === state) since = null
      else {
        since ??= now
        if (now - since >= (looking ? clearMs : awayMs)) { state = target; since = null }
      }
      return state
    },
  }
}
