// Pure identity + camera-health rules (no DOM, no Human, no mediapipe). Fail closed everywhere.
import { createHysteresis, isLooking, DEFAULT_ENVELOPE, DEFAULT_SENSITIVITY, DEFAULT_AWAY_MS, DEFAULT_CLEAR_MS } from "./gaze_state.js"

// ponytail: tuning knobs. MATCH_THRESHOLD is human.match.similarity (0..1, faceres) against the best enrolled sample;
// raise if strangers get through, lower if the owner is rejected in bad light.
export const MATCH_THRESHOLD = 0.6
export const ANTISPOOF_MIN = 0.5
export const LIVENESS_MIN = 0.5
export const EAR_MIN = 0.3 // movenet keypoint score; ears are its weakest points
export const EAR_BOX_SLACK = 0.25 // of face box height: ears may sit this far above/below the box
export const EAR_REACH = 0.6 // of face box width: how far outside its side edge an ear may be (hair, earrings, ear tilt)
export const VERIFY_TTL_MS = 2500
export const OWNER_TRACK_DIST = 0.25 // normalized frame distance an owner face may move between gaze frames
export const BLACK_MEAN = 12 // of 255
export const FLAT_STD = 3
export const FROZEN_MS = 2000

export const MESSAGES = {
  not_enrolled: "Face ID is not set up",
  no_face: "No face in view",
  not_owner: "Face not recognized",
  multiple_match: "Face not recognized",
  spoof: "Could not confirm a real face",
  ears: "Show both ears: remove masks, scarves or hair covering them",
  stale: "Checking who is looking",
  other_looking: "Someone else is looking at the screen",
  away: "You looked away",
  dark: "Camera image is dark or covered",
  frozen: "Camera feed stopped",
}

// ponytail: EAR_BOX_SLACK / EAR_REACH are the tuning knobs for "these ears belong to this face".
// bodies: [{ leftEar: {score,x,y}, rightEar: {score,x,y} }] (normalized frame coords), box: face { x, y, w, h }.
// True when ONE body has both ears confident, within the face's vertical band, one on each side of the face centre
// (no reliance on left/right naming, so mirrored video is fine) and near its side edge of the box.
export function earsOnFace(bodies = [], box) {
  if (!box) return false
  const cx = box.x + box.w / 2, slack = EAR_BOX_SLACK * box.h, reach = EAR_REACH * box.w
  const ok = (e, side) =>
    e && e.score >= EAR_MIN && e.y >= box.y - slack && e.y <= box.y + box.h + slack &&
    (side < 0 ? e.x < cx && e.x >= box.x - reach : e.x > cx && e.x <= box.x + box.w + reach)
  return bodies.some((b) => {
    const [a, c] = [b.leftEar, b.rightEar]
    return (ok(a, -1) && ok(c, 1)) || (ok(a, 1) && ok(c, -1))
  })
}

// faces: [{ similarity, real, live, center, box }]. Owner = exactly one matching face.
export function verifyOwner({ faces = [], bodies = [] } = {}) {
  if (!faces.length) return { ok: false, reason: "no_face" }
  const matched = faces.filter((f) => f.similarity >= MATCH_THRESHOLD)
  if (matched.length !== 1) return { ok: false, reason: matched.length ? "multiple_match" : "not_owner" }
  const o = matched[0]
  if (!(o.real >= ANTISPOOF_MIN) || !(o.live >= LIVENESS_MIN)) return { ok: false, reason: "spoof", center: o.center }
  if (!earsOnFace(bodies, o.box)) return { ok: false, reason: "ears", center: o.center }
  return { ok: true, center: o.center }
}

// Enrollment checklist: one face / ears / real person / camera. Each is a boolean the UI turns into a chip.
export function enrollChecks({ faces = [], bodies = [], camera = { ok: true } } = {}) {
  const one = faces.length === 1
  const f = faces[0]
  return {
    oneFace: one,
    ears: one && earsOnFace(bodies, f.box),
    real: one && f.real >= ANTISPOOF_MIN && f.live >= LIVENESS_MIN,
    camera: !!camera.ok,
  }
}
export const allChecks = (c) => c.oneFace && c.ears && c.real && c.camera

// ---- camera health ----
// rgba: ImageData.data of a tiny frame. Mean/stddev of luminance.
export function lumaStats(rgba) {
  const n = rgba.length >> 2
  if (!n) return { mean: 0, std: 0 }
  let sum = 0, sq = 0
  for (let i = 0; i < n; i++) {
    const y = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2]
    sum += y
    sq += y * y
  }
  const mean = sum / n
  return { mean, std: Math.sqrt(Math.max(0, sq / n - mean * mean)) }
}

// Frozen = the frame key (video.currentTime) has not advanced for FROZEN_MS.
export function createFrozenWatch(ms = FROZEN_MS) {
  let key, since = null
  return (k, now) => {
    if (k !== key || since === null) { key = k; since = now; return false }
    return now - since > ms
  }
}

export function cameraStatus({ stats, frozen = false, muted = false } = {}) {
  if (muted || frozen) return { ok: false, reason: "frozen" }
  if (!stats || stats.mean < BLACK_MEAN || stats.std < FLAT_STD) return { ok: false, reason: "dark" }
  return { ok: true }
}

// ---- guard: everything the haze decision needs ----
// Owner's mediapipe face = the one nearest the last verified position; any other looking face hazes at once.
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)

// Identity failures caused by simply turning away (no face, ears hidden) get the same awayMs grace as a glance.
// Anything that could be someone else (not_owner, spoof, ...) hazes at once.
const SOFT = ["no_face", "ears"]

export function createGuard({ envelope = DEFAULT_ENVELOPE, sensitivity = DEFAULT_SENSITIVITY, awayMs = DEFAULT_AWAY_MS, clearMs = DEFAULT_CLEAR_MS, enrolled = false, ttl = VERIFY_TTL_MS } = {}) {
  const hyst = createHysteresis({ awayMs, clearMs })
  // camera unknown until the first health check, so start "stale" (quiet haze)
  let verified = null, camera = { ok: false, reason: "stale" }, owner = null, othersLooking = false, now0 = 0, lastOk = null
  const look = (f) => isLooking(f, envelope, sensitivity)
  return {
    setCalibration(e) { envelope = e },
    setTuning(t = {}) {
      sensitivity = t.sensitivity ?? sensitivity
      awayMs = t.awayMs ?? awayMs
      hyst.setDelays(t.awayMs, t.clearMs)
    },
    setEnrolled(e) { enrolled = e },
    setCamera(c) { camera = c },
    reset() { hyst.reset(); verified = null; owner = null; othersLooking = false; lastOk = null },
    // result of verifyOwner() at time `now`
    verify(r, now) {
      verified = { ...r, at: now }
      if (r.ok) lastOk = now
      if (r.center) owner = r.center
    },
    // faces: [{ yaw, pitch, h, v, center }] from the fast mediapipe loop
    gaze(faces, now) {
      now0 = now
      let mine = null, best = OWNER_TRACK_DIST
      if (owner) for (const f of faces) { const d = f.center ? dist(f.center, owner) : Infinity; if (d <= best) { best = d; mine = f } }
      if (mine?.center) owner = mine.center
      othersLooking = faces.some((f) => f !== mine && look(f))
      hyst.step(!!mine && look(mine), now)
    },
    decision(now = now0) {
      const d = (reason) => ({ hazy: true, reason })
      if (!enrolled) return d("not_enrolled")
      if (!camera.ok) return d(camera.reason)
      if (!verified) return d("stale")
      if (now - verified.at > ttl) return d("stale")
      if (!verified.ok) {
        const grace = SOFT.includes(verified.reason) && lastOk !== null && now - lastOk < awayMs
        if (!grace) return d(verified.reason)
      }
      if (othersLooking) return d("other_looking")
      if (hyst.state !== "looking") return d("away")
      return { hazy: false, reason: null }
    },
  }
}
