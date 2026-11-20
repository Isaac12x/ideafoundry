import { test } from "node:test"
import assert from "node:assert/strict"
import {
  isLooking, calibrate, createHysteresis, extractFeatures, loadBaseline, saveBaseline, hasBaseline,
  MAX_YAW_DEG, AWAY_AFTER_MS, LOOK_AFTER_MS,
} from "../../app/javascript/privacy_gaze/gaze_state.js"

const f = (o = {}) => ({ yaw: 0, pitch: 0, h: 0, v: 0, ...o })

test("no face is away", () => {
  assert.equal(isLooking(null), false)
})

test("within thresholds is looking, beyond any one is away", () => {
  assert.equal(isLooking(f({ yaw: MAX_YAW_DEG - 1, pitch: -10, h: 0.2 })), true)
  assert.equal(isLooking(f({ yaw: MAX_YAW_DEG + 1 })), false)
  assert.equal(isLooking(f({ pitch: 30 })), false)
  assert.equal(isLooking(f({ h: 0.5 })), false)
  assert.equal(isLooking(f({ v: -0.6 })), false)
})

test("baseline offsets the thresholds (camera above the screen)", () => {
  const baseline = { yaw: 0, pitch: -15, h: 0, v: 0 }
  assert.equal(isLooking(f({ pitch: -15 }), baseline), true)
  assert.equal(isLooking(f({ pitch: -15 }), undefined), true)
  assert.equal(isLooking(f({ pitch: -40 }), baseline), false)
  assert.equal(isLooking(f({ pitch: 10 }), baseline), false)
})

test("calibrate takes the median and ignores missing frames", () => {
  const b = calibrate([f({ yaw: 1 }), null, f({ yaw: 3 }), f({ yaw: 100 }), f({ yaw: 2 })])
  assert.equal(b.yaw, 2.5)
  assert.equal(calibrate([null]), null)
})

test("hysteresis: starts away, hazes after AWAY_AFTER_MS, clears after LOOK_AFTER_MS", () => {
  const h = createHysteresis()
  assert.equal(h.step(false, 0), "away")
  assert.equal(h.step(true, 1000), "away")
  assert.equal(h.step(true, 1000 + LOOK_AFTER_MS - 1), "away")
  assert.equal(h.step(true, 1000 + LOOK_AFTER_MS), "looking")
  // a glance shorter than the delay does not haze
  assert.equal(h.step(false, 2000), "looking")
  assert.equal(h.step(true, 2000 + AWAY_AFTER_MS - 1), "looking")
  // and the interrupted away run restarts its clock
  assert.equal(h.step(false, 3000), "looking")
  assert.equal(h.step(false, 3000 + AWAY_AFTER_MS - 1), "looking")
  assert.equal(h.step(false, 3000 + AWAY_AFTER_MS), "away")
  h.step(true, 4000); h.step(true, 5000)
  h.reset()
  assert.equal(h.state, "away")
})

test("extractFeatures: null without a face, zero pose for identity matrix", () => {
  assert.equal(extractFeatures({}), null)
  const m = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
  const r = extractFeatures({
    facialTransformationMatrixes: [{ data: m }],
    faceBlendshapes: [{ categories: [{ categoryName: "eyeLookOutLeft", score: 0.4 }] }],
  })
  assert.ok(Math.abs(r.yaw) < 1e-9)
  assert.ok(Math.abs(r.pitch) < 1e-9)
  assert.ok(Math.abs(r.h - 0.2) < 1e-9)
})

test("baseline storage survives a throwing localStorage", () => {
  const boom = { getItem() { throw new Error("no") }, setItem() { throw new Error("no") } }
  assert.equal(saveBaseline(f(), boom), false)
  assert.equal(hasBaseline(boom), false)
  assert.equal(loadBaseline(boom).yaw, 0)
  const mem = { d: {}, getItem(k) { return this.d[k] ?? null }, setItem(k, v) { this.d[k] = v } }
  saveBaseline(f({ pitch: -12 }), mem)
  assert.equal(loadBaseline(mem).pitch, -12)
})

test("hysteresis can start looking (Turbo resume) and still hazes after the away delay", () => {
  const h = createHysteresis({ initial: "looking" })
  assert.equal(h.step(false, 0), "looking")
  assert.equal(h.step(false, 499), "looking")
  assert.equal(h.step(false, 500), "away")
})

// ---- identity + camera health ----
import {
  verifyOwner, enrollChecks, allChecks, createGuard, lumaStats, cameraStatus, createFrozenWatch,
  MATCH_THRESHOLD, VERIFY_TTL_MS, FROZEN_MS,
} from "../../app/javascript/privacy_gaze/identity_state.js"

const ME = { x: 0.4, y: 0.5 }, THEM = { x: 0.8, y: 0.5 }
const face = (o = {}) => ({ similarity: 0.9, real: 0.9, live: 0.9, center: ME, box: BOX, ...o })
// face box centred on ME; ears at the box sides, mid-height
const BOX = { x: 0.3, y: 0.3, w: 0.2, h: 0.4 }
const ear = (x, y = 0.5, score = 0.8) => ({ score, x, y })
const ears = [{ leftEar: ear(0.28), rightEar: ear(0.52) }]
const mp = (center, o = {}) => ({ ...f(o), center })

// guard with a healthy camera, enrolled; owner verified at t=0
const guard = (verifyArg = { faces: [face()], bodies: ears }) => {
  const g = createGuard({ enrolled: true })
  g.setCamera({ ok: true })
  g.verify(verifyOwner(verifyArg), 0)
  return g
}
// drive gaze frames long enough for the look hysteresis to settle
const look = (g, faces, from = 0, to = 400) => { for (let t = from; t <= to; t += 80) g.gaze(faces, t) }

test("verifyOwner: owner alone passes; stranger, spoof, missing ears, no face fail", () => {
  assert.equal(verifyOwner({ faces: [face()], bodies: ears }).ok, true)
  assert.equal(verifyOwner({ faces: [face({ similarity: MATCH_THRESHOLD - 0.01 })], bodies: ears }).reason, "not_owner")
  assert.equal(verifyOwner({ faces: [face({ real: 0.1 })], bodies: ears }).reason, "spoof")
  assert.equal(verifyOwner({ faces: [face({ live: 0.1 })], bodies: ears }).reason, "spoof")
  assert.equal(verifyOwner({ faces: [face()], bodies: [{ leftEar: ear(0.28), rightEar: ear(0.52, 0.5, 0.05) }] }).reason, "ears")
  assert.equal(verifyOwner({ faces: [face()], bodies: [] }).reason, "ears")
  assert.equal(verifyOwner({ faces: [], bodies: ears }).reason, "no_face")
  assert.equal(verifyOwner({ faces: [face(), face()], bodies: ears }).reason, "multiple_match")
  // owner plus a stranger: still verified, the stranger is unmatched
  assert.equal(verifyOwner({ faces: [face(), face({ similarity: 0.1, center: THEM })], bodies: ears }).ok, true)
})

test("ears must belong to the matched face", () => {
  const v = (bodies) => verifyOwner({ faces: [face()], bodies })
  assert.equal(v(ears).ok, true)
  assert.equal(v([{ leftEar: ear(0.52), rightEar: ear(0.28) }]).ok, true) // mirrored naming
  // a second person's ears elsewhere in the frame
  assert.equal(v([{ leftEar: ear(0.78), rightEar: ear(0.92) }]).reason, "ears")
  assert.equal(v([{ leftEar: ear(0.7, 0.5), rightEar: ear(0.95, 0.5) }]).reason, "ears")
  // ears split across two bodies do not count
  assert.equal(v([{ leftEar: ear(0.28), rightEar: null }, { leftEar: null, rightEar: ear(0.52) }]).reason, "ears")
  // both on the same side of the face
  assert.equal(v([{ leftEar: ear(0.27), rightEar: ear(0.29) }]).reason, "ears")
  // far below the face
  assert.equal(v([{ leftEar: ear(0.28, 0.95), rightEar: ear(0.52, 0.95) }]).reason, "ears")
  // low confidence
  assert.equal(v([{ leftEar: ear(0.28, 0.5, 0.1), rightEar: ear(0.52) }]).reason, "ears")
  // a real body elsewhere plus the owner's own: still ok
  assert.equal(v([{ leftEar: ear(0.78), rightEar: ear(0.92) }, ...ears]).ok, true)
})

test("guard: owner alone looking clears", () => {
  const g = guard()
  look(g, [mp(ME)])
  assert.equal(g.decision(400).hazy, false)
})

test("guard: stranger alone looking hazes", () => {
  const g = guard({ faces: [face({ similarity: 0.1 })], bodies: ears })
  look(g, [mp(THEM)])
  assert.deepEqual(g.decision(400), { hazy: true, reason: "not_owner" })
})

test("guard: owner + stranger both looking hazes; stranger looking away does not", () => {
  const g = guard({ faces: [face(), face({ similarity: 0.1, center: THEM })], bodies: ears })
  look(g, [mp(ME), mp(THEM)])
  assert.deepEqual(g.decision(400), { hazy: true, reason: "other_looking" })
  look(g, [mp(ME), mp(THEM, { yaw: 60 })], 480, 900)
  assert.equal(g.decision(900).hazy, false)
})

test("guard: owner looking away hazes; ears missing / spoof never clear", () => {
  const g = guard()
  look(g, [mp(ME, { yaw: 60 })])
  assert.equal(g.decision(400).reason, "away")
  for (const [arg, reason] of [
    [{ faces: [face()], bodies: [{ leftEar: ear(0.28), rightEar: ear(0.52, 0.5, 0) }] }, "ears"],
    [{ faces: [face({ real: 0 })], bodies: ears }, "spoof"],
  ]) {
    const h = guard(arg)
    look(h, [mp(ME)])
    assert.deepEqual(h.decision(400), { hazy: true, reason })
  }
})

test("guard: verification goes stale after the TTL; not enrolled always hazes", () => {
  const g = guard()
  look(g, [mp(ME)], 0, 2000)
  assert.equal(g.decision(VERIFY_TTL_MS).hazy, false)
  assert.deepEqual(g.decision(VERIFY_TTL_MS + 1), { hazy: true, reason: "stale" })
  const n = createGuard({ enrolled: false })
  n.setCamera({ ok: true })
  assert.equal(n.decision(0).reason, "not_enrolled")
})

test("guard: bad camera hazes even with a verified owner looking", () => {
  const g = guard()
  look(g, [mp(ME)])
  g.setCamera(cameraStatus({ stats: { mean: 3, std: 10 } }))
  assert.deepEqual(g.decision(400), { hazy: true, reason: "dark" })
})

test("enrollChecks: all four must pass", () => {
  const ok = { faces: [face()], bodies: ears, camera: { ok: true } }
  assert.equal(allChecks(enrollChecks(ok)), true)
  assert.equal(enrollChecks({ ...ok, faces: [face(), face()] }).oneFace, false)
  assert.equal(enrollChecks({ ...ok, bodies: [{ leftEar: ear(0.28), rightEar: null }] }).ears, false)
  assert.equal(enrollChecks({ ...ok, faces: [face({ real: 0.2 })] }).real, false)
  assert.equal(allChecks(enrollChecks({ ...ok, camera: { ok: false } })), false)
})

const px = (n, fn) => Uint8ClampedArray.from({ length: n * 4 }, (_, i) => (i % 4 === 3 ? 255 : fn(i >> 2)))

test("camera health: black, flat, ok, frozen, muted", () => {
  const black = lumaStats(px(192, () => 2))
  const flat = lumaStats(px(192, () => 128))
  const good = lumaStats(px(192, (p) => (p % 2 ? 60 : 180)))
  assert.equal(cameraStatus({ stats: black }).reason, "dark")
  assert.equal(cameraStatus({ stats: flat }).reason, "dark")
  assert.equal(cameraStatus({ stats: good }).ok, true)
  assert.equal(cameraStatus({}).ok, false) // no frame yet
  assert.equal(cameraStatus({ stats: good, muted: true }).reason, "frozen")
  const frozen = createFrozenWatch()
  assert.equal(frozen(1.0, 0), false)
  assert.equal(frozen(1.4, 500), false) // advancing
  assert.equal(frozen(1.4, 500 + FROZEN_MS), false)
  assert.equal(frozen(1.4, 500 + FROZEN_MS + 1), true) // stuck for > 2s
  assert.equal(cameraStatus({ stats: good, frozen: true }).reason, "frozen")
  assert.equal(frozen(2.0, 5000), false) // recovers when frames advance
})
