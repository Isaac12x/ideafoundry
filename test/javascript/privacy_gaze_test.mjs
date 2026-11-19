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
