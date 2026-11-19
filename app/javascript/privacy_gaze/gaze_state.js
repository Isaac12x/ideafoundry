// Pure gaze logic (no DOM, no mediapipe): classify a frame as looking/away and debounce the result.

// ponytail: calibration is the tuning knob. These are deltas from the per-device baseline (the camera sits above the
// screen, so "looking at the screen" is never yaw/pitch 0). Widen if the haze flickers, tighten if it is too lax.
export const MAX_YAW_DEG = 25;
export const MAX_PITCH_DEG = 20;
export const MAX_EYE_H = 0.35; // blendshape units, eyeLookIn/Out
export const MAX_EYE_V = 0.4; // eyeLookUp/Down (noisier)
export const AWAY_AFTER_MS = 500;
export const LOOK_AFTER_MS = 150;
export const DEFAULT_BASELINE = { yaw: 0, pitch: 0, h: 0, v: 0 };
const STORE_KEY = "privacy-gaze:baseline";

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n))
const deg = (rad) => (rad * 180) / Math.PI
const score = (shapes, name) => shapes?.find((c) => c.categoryName === name)?.score ?? 0

// FaceLandmarker result -> { yaw, pitch, h, v } or null when no face. matrix is column-major 4x4.
export function extractFeatures(result) {
  const m = result?.facialTransformationMatrixes?.[0]?.data
  const shapes = result?.faceBlendshapes?.[0]?.categories
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

export function isLooking(f, baseline = DEFAULT_BASELINE) {
  if (!f) return false // no face = away
  const b = { ...DEFAULT_BASELINE, ...baseline }
  return (
    Math.abs(f.yaw - b.yaw) <= MAX_YAW_DEG &&
    Math.abs(f.pitch - b.pitch) <= MAX_PITCH_DEG &&
    Math.abs(f.h - b.h) <= MAX_EYE_H &&
    Math.abs(f.v - b.v) <= MAX_EYE_V
  )
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b)
  const i = s.length >> 1
  return s.length % 2 ? s[i] : (s[i - 1] + s[i]) / 2
}

// Median of feature samples (looking at the middle of the screen); null when there are none.
export function calibrate(samples) {
  const good = samples.filter(Boolean)
  if (!good.length) return null
  return Object.fromEntries(["yaw", "pitch", "h", "v"].map((k) => [k, median(good.map((f) => f[k]))]))
}

// Starts "away" (fail closed) unless told otherwise. Flips only after the opposite reading has held for the whole delay.
export function createHysteresis({ awayMs = AWAY_AFTER_MS, lookMs = LOOK_AFTER_MS, initial = "away" } = {}) {
  let state = initial, since = null
  return {
    get state() { return state },
    reset() { state = "away"; since = null },
    step(looking, now) {
      const target = looking ? "looking" : "away"
      if (target === state) since = null
      else {
        since ??= now
        if (now - since >= (looking ? lookMs : awayMs)) { state = target; since = null }
      }
      return state
    },
  }
}

export function loadBaseline(storage = globalThis.localStorage) {
  try { return { ...DEFAULT_BASELINE, ...JSON.parse(storage.getItem(STORE_KEY)) } } catch { return DEFAULT_BASELINE }
}
export function hasBaseline(storage = globalThis.localStorage) {
  try { return !!storage.getItem(STORE_KEY) } catch { return false }
}
export function saveBaseline(b, storage = globalThis.localStorage) {
  try { storage.setItem(STORE_KEY, JSON.stringify(b)); return true } catch { return false }
}
