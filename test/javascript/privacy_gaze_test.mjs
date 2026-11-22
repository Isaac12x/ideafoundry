import { test } from "node:test"
import assert from "node:assert/strict"
import {
  isLooking, margins, marginScale, pointMedian, buildEnvelope, createHysteresis, extractFeatures,
  loadEnvelope, saveEnvelope, hasEnvelope, DEFAULT_ENVELOPE, screenKey, loadProfiles, renameProfile, deleteProfile, defaultScreenName, DEFAULT_AWAY_MS, DEFAULT_CLEAR_MS, CALIBRATION_POINTS,
} from "../../app/javascript/privacy_gaze/gaze_state.js"
import { devtoolsOpen, devtoolsKey, windowGap, hazeVars, hazeOffAllowed } from "../../app/javascript/lib/privacy_guard.mjs"
import { privacyToggleAllowed, DEFAULT_BINDINGS, matches, platformBinding, binding } from "../../app/javascript/lib/shortcut_bindings.mjs"

const f = (o = {}) => ({ yaw: 0, pitch: 0, h: 0, v: 0, ...o })

test("no face is away", () => {
  assert.equal(isLooking(null), false)
})

test("uncalibrated defaults are generous: wide yaw / pitch still looking", () => {
  assert.equal(isLooking(f({ yaw: 26, pitch: -20, h: 0.3 })), true)
  assert.equal(isLooking(f({ yaw: 40 })), false)
  assert.equal(isLooking(f({ pitch: 30 })), false)
  assert.equal(isLooking(f({ v: -0.7 })), false)
})

test("margins scale monotonically with sensitivity: 25deg at 1, 12 at 5, 5 at 10", () => {
  assert.ok(Math.abs(margins(1).yaw - 25) < 1e-9)
  assert.ok(Math.abs(margins(5).yaw - 12) < 1e-9)
  assert.ok(Math.abs(margins(10).yaw - 5) < 1e-9)
  for (let s = 1; s < 10; s++) for (const k of ["yaw", "pitch", "h", "v"]) assert.ok(margins(s)[k] > margins(s + 1)[k], `${k} at ${s}`)
  assert.equal(marginScale(undefined), 1)
  assert.equal(marginScale(99), marginScale(10)) // clamped
})

// 5-point calibration: centre + the four corners; the camera sits above the screen so pitch is offset
const pt = (o) => Array.from({ length: 6 }, () => f(o))
const perPoint = [
  pt({ yaw: 0, pitch: -10 }), pt({ yaw: -20, pitch: -2 }), pt({ yaw: 20, pitch: -2 }), pt({ yaw: 20, pitch: -22 }), pt({ yaw: -20, pitch: -22 }),
]

test("buildEnvelope: min/max over the per-point medians, centre first; null when any point is unseen", () => {
  const e = buildEnvelope(perPoint)
  assert.equal(e.min.yaw, -20); assert.equal(e.max.yaw, 20)
  assert.equal(e.min.pitch, -22); assert.equal(e.max.pitch, -2)
  assert.equal(e.center.pitch, -10)
  assert.equal(buildEnvelope([...perPoint.slice(0, 4), [f(), null, null]]), null) // too few samples at a point
  assert.equal(buildEnvelope([]), null)
  assert.equal(pointMedian([f({ yaw: 1 }), null, f({ yaw: 3 }), f({ yaw: 100 }), f({ yaw: 2 }), f({ yaw: 2 })]).yaw, 2)
  assert.equal(CALIBRATION_POINTS.length, 5)
  assert.deepEqual(CALIBRATION_POINTS[0], { x: 0.5, y: 0.5 })
})

test("envelope: every corner is looking, beyond-margin is away, stricter sensitivity shrinks the margin", () => {
  const e = buildEnvelope(perPoint)
  for (const p of perPoint) assert.equal(isLooking(p[0], e, 5), true)
  assert.equal(isLooking(f({ yaw: 30, pitch: -10 }), e, 5), true) // inside the default 12deg margin
  assert.equal(isLooking(f({ yaw: 33, pitch: -10 }), e, 5), false) // 13deg beyond the edge
  assert.equal(isLooking(f({ yaw: 33, pitch: -10 }), e, 1), true) // relaxed: 25deg margin
  assert.equal(isLooking(f({ yaw: 26, pitch: -10 }), e, 10), false) // strict: 5deg margin
  assert.equal(isLooking(f({ yaw: 24, pitch: -10 }), e, 10), true)
  assert.equal(isLooking(f({ yaw: 0, pitch: 30 }), e, 5), false) // looking up/away
  // eyes count too
  assert.equal(isLooking(f({ yaw: 0, pitch: -10, h: 0.5 }), e, 5), false)
})

test("a malformed envelope falls back to the generous defaults", () => {
  assert.equal(isLooking(f({ yaw: 20 }), { min: null }), true)
  assert.equal(isLooking(f({ yaw: 20 }), undefined), true)
})

test("hysteresis: starts away, clears after clearMs, hazes only after awayMs", () => {
  const h = createHysteresis()
  assert.equal(DEFAULT_AWAY_MS, 2500); assert.equal(DEFAULT_CLEAR_MS, 150)
  assert.equal(h.step(false, 0), "away")
  assert.equal(h.step(true, 1000), "away")
  assert.equal(h.step(true, 1000 + DEFAULT_CLEAR_MS - 1), "away")
  assert.equal(h.step(true, 1000 + DEFAULT_CLEAR_MS), "looking")
  // a glance (even ~2s) shorter than awayMs never hazes, and the interrupted run restarts its clock
  assert.equal(h.step(false, 2000), "looking")
  assert.equal(h.step(false, 2000 + DEFAULT_AWAY_MS - 1), "looking")
  assert.equal(h.step(true, 2000 + DEFAULT_AWAY_MS), "looking")
  assert.equal(h.step(false, 5000), "looking")
  assert.equal(h.step(false, 5000 + DEFAULT_AWAY_MS - 1), "looking")
  assert.equal(h.step(false, 5000 + DEFAULT_AWAY_MS), "away")
  h.step(true, 9000); h.step(true, 10000)
  h.reset()
  assert.equal(h.state, "away")
})

test("hysteresis honours custom delays and can start looking (Turbo resume)", () => {
  const h = createHysteresis({ awayMs: 800, clearMs: 0, initial: "looking" })
  assert.equal(h.step(false, 0), "looking")
  assert.equal(h.step(false, 799), "looking")
  assert.equal(h.step(false, 800), "away")
  assert.equal(h.step(true, 900), "looking") // clearMs 0: immediate
  h.setDelays(100, 100)
  assert.equal(h.step(false, 1000), "looking")
  assert.equal(h.step(false, 1100), "away")
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

test("envelope storage survives a throwing localStorage and rejects junk", () => {
  const boom = { getItem() { throw new Error("no") }, setItem() { throw new Error("no") } }
  const e = buildEnvelope(perPoint)
  assert.equal(saveEnvelope(e, boom), false)
  assert.equal(hasEnvelope(boom), false)
  assert.equal(loadEnvelope(boom), DEFAULT_ENVELOPE)
  const mem = { d: {}, getItem(k) { return this.d[k] ?? null }, setItem(k, v) { this.d[k] = v } }
  assert.equal(hasEnvelope(mem), false)
  saveEnvelope(e, mem)
  assert.equal(hasEnvelope(mem), true)
  assert.equal(loadEnvelope(mem).min.yaw, -20)
  mem.d["privacy-gaze:profiles"] = '{"profiles":[{"key":"unknown","envelope":{"min":1}}]}'
  assert.equal(loadEnvelope(mem), DEFAULT_ENVELOPE)
})

const mem = () => ({ d: {}, getItem(k) { return this.d[k] ?? null }, setItem(k, v) { this.d[k] = v }, removeItem(k) { delete this.d[k] } })
const laptop = { width: 1512, height: 982, availLeft: 0, availTop: 38, isInternal: true }
const above = { width: 2560, height: 1440, availLeft: 0, availTop: -1440 }
const beside = { ...above, availLeft: 1512, availTop: 0 }

test("screenKey: size + position; a monitor above differs from the same one beside; no screen = unknown", () => {
  assert.equal(screenKey(laptop), "1512x982@0,38")
  assert.notEqual(screenKey(above), screenKey(beside))
  assert.notEqual(screenKey(above), screenKey(laptop))
  assert.equal(screenKey({ ...laptop, devicePixelRatio: 3 }), screenKey(laptop)) // zoom/dpr must not change the identity
  assert.equal(screenKey({ width: 800, height: 600 }), "800x600@0,0") // no availLeft/availTop (Safari/Firefox)
  assert.equal(screenKey(undefined), "unknown")
  assert.equal(screenKey({}), "unknown")
  assert.match(defaultScreenName(laptop), /built-in/)
  assert.equal(defaultScreenName(above, "LG UltraFine"), "LG UltraFine")
})

test("profiles: one per screen, auto-selected by screen, recalibrate replaces, default for uncalibrated", () => {
  const st = mem()
  const e1 = buildEnvelope(perPoint)
  const e2 = { ...e1, min: { ...e1.min, yaw: -40 } }
  assert.equal(hasEnvelope(st, laptop), false)
  saveEnvelope(e1, st, laptop)
  assert.equal(hasEnvelope(st, laptop), true)
  assert.equal(hasEnvelope(st, above), false) // the other screen is uncalibrated: prompt + defaults
  assert.equal(loadEnvelope(st, above), DEFAULT_ENVELOPE)
  saveEnvelope(e2, st, above, "Desk monitor")
  assert.equal(loadEnvelope(st, above).min.yaw, -40)
  assert.equal(loadEnvelope(st, laptop).min.yaw, -20) // untouched
  assert.deepEqual(loadProfiles(st, laptop).map((p) => p.name), ["1512\u00d7982 screen (built-in)", "Desk monitor"])
  saveEnvelope(e1, st, above) // recalibrate keeps the (renamed) name, replaces the envelope
  assert.equal(loadProfiles(st, laptop).length, 2)
  assert.equal(loadEnvelope(st, above).min.yaw, -20)
  assert.equal(loadProfiles(st, laptop)[1].name, "Desk monitor")
})

test("profiles: rename (trimmed, non-empty) and delete", () => {
  const st = mem()
  saveEnvelope(buildEnvelope(perPoint), st, laptop)
  const key = screenKey(laptop)
  assert.equal(renameProfile(key, "  Laptop  ", st), true)
  assert.equal(loadProfiles(st, laptop)[0].name, "Laptop")
  assert.equal(renameProfile(key, "   ", st), false)
  assert.equal(loadProfiles(st, laptop)[0].name, "Laptop")
  deleteProfile(key, st)
  assert.equal(hasEnvelope(st, laptop), false)
  assert.deepEqual(loadProfiles(st, laptop), [])
})

test("profiles: the legacy single envelope becomes the first profile (of the current screen) and is removed", () => {
  const st = mem()
  st.d["privacy-gaze:envelope"] = JSON.stringify(buildEnvelope(perPoint))
  assert.equal(hasEnvelope(st, laptop), true)
  assert.equal(st.d["privacy-gaze:envelope"], undefined)
  assert.equal(loadProfiles(st, above).length, 1)
  assert.equal(hasEnvelope(st, above), false)
  assert.equal(loadEnvelope(st, laptop).min.yaw, -20)
  const junk = mem()
  junk.d["privacy-gaze:envelope"] = '{"min":1}'
  assert.deepEqual(loadProfiles(junk, laptop), [])
})

// ---- devtools + shortcut guards ----
test("devtoolsOpen: only a gap increase of more than 160px over the clear baseline counts", () => {
  const w = (o) => ({ outerWidth: 1400, innerWidth: 1400, outerHeight: 900, innerHeight: 800, ...o })
  const base = windowGap(w())
  assert.equal(devtoolsOpen(windowGap(w()), base), false)
  assert.equal(devtoolsOpen(windowGap(w({ innerWidth: 1000 })), base), true) // docked right
  assert.equal(devtoolsOpen(windowGap(w({ innerHeight: 600 })), base), true) // docked bottom
  assert.equal(devtoolsOpen(windowGap(w({ innerWidth: 1240 })), base), false) // exactly 160
  // sidebar already open at baseline (Arc / side panel): not devtools
  const side = windowGap(w({ innerWidth: 1150 }))
  assert.equal(devtoolsOpen(side, side), false)
  assert.equal(devtoolsOpen(windowGap(w({ innerWidth: 950 })), side), true) // baseline + 200
  assert.equal(devtoolsOpen(windowGap(w({ innerWidth: 1400 })), side), false) // gap shrinks
  assert.equal(devtoolsOpen(null, base), false)
  assert.equal(devtoolsOpen(base, null), false)
})

test("devtoolsKey: F12, Ctrl/Cmd+Shift+I/J/C, Cmd+Alt+I/J/C (by code), Ctrl/Cmd+U", () => {
  const k = (o) => devtoolsKey({ key: "", code: "", ...o })
  assert.equal(k({ key: "F12", code: "F12" }), true)
  assert.equal(k({ key: "I", code: "KeyI", ctrlKey: true, shiftKey: true }), true)
  assert.equal(k({ key: "j", code: "KeyJ", metaKey: true, shiftKey: true }), true)
  assert.equal(k({ key: "C", code: "KeyC", ctrlKey: true, shiftKey: true }), true)
  assert.equal(k({ key: "ˆ", code: "KeyI", metaKey: true, altKey: true }), true) // Alt changes e.key on Mac
  assert.equal(k({ key: "∆", code: "KeyJ", metaKey: true, altKey: true }), true)
  assert.equal(k({ key: "ç", code: "KeyC", metaKey: true, altKey: true }), true)
  assert.equal(k({ key: "u", code: "KeyU", ctrlKey: true }), true)
  assert.equal(k({ key: "u", code: "KeyU", metaKey: true }), true)
  assert.equal(k({ key: "i", code: "KeyI", ctrlKey: true }), false) // plain Ctrl+I (italic)
  assert.equal(k({ key: "c", code: "KeyC", ctrlKey: true }), false) // copy
  assert.equal(k({ key: "u", code: "KeyU" }), false)
})

test("privacy shortcut: ON always allowed; OFF only while the owner is verified looking", () => {
  assert.equal(privacyToggleAllowed(false, undefined), true)
  assert.equal(privacyToggleAllowed(false, "false"), true)
  assert.equal(privacyToggleAllowed(true, "true"), true)
  assert.equal(privacyToggleAllowed(true, true), true)
  assert.equal(privacyToggleAllowed(true, "false"), false) // hazed / away / unknown face
  assert.equal(privacyToggleAllowed(true, undefined), false) // no reading (inactive page): fail closed
})

test("privacy_haze: Cmd+Shift+G on Mac (native opt-out), Alt+Shift+G elsewhere", () => {
  assert.equal(DEFAULT_BINDINGS.privacy_haze.key, "Ctrl/Cmd+Shift+G")
  const ev = (o) => ({ key: "G", code: "KeyG", metaKey: false, ctrlKey: false, altKey: false, shiftKey: true, ...o })
  const plat = (p) => Object.defineProperty(globalThis, "navigator", { value: { platform: p }, configurable: true })
  plat("MacIntel")
  assert.equal(binding("privacy_haze"), "Ctrl/Cmd+Shift+G")
  assert.ok(matches(binding("privacy_haze"), ev({ metaKey: true })))
  assert.equal(binding("save"), "Ctrl+S") // other browser-owned keys still move
  plat("Win32")
  assert.equal(binding("privacy_haze"), "Alt+Shift+G")
  assert.ok(matches(binding("privacy_haze"), ev({ altKey: true })))
  delete globalThis.navigator
})

test("hazeVars: monotonic, 1 = light veil, 10 = near invisible, bad input = default", () => {
  const num = (s, k) => parseFloat(hazeVars(s)[k])
  for (let s = 1; s < 10; s++) {
    assert.ok(num(s, "--privacy-haze-opacity") > num(s + 1, "--privacy-haze-opacity"))
    assert.ok(num(s, "--privacy-haze-blur") < num(s + 1, "--privacy-haze-blur"))
  }
  assert.ok(num(1, "--privacy-haze-opacity") >= 0.4)
  assert.ok(num(10, "--privacy-haze-opacity") <= 0.05)
  assert.deepEqual(hazeVars(undefined), hazeVars(6))
  assert.deepEqual(hazeVars(99), hazeVars(10))
  assert.deepEqual(hazeVars(0), hazeVars(6))
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

test("guard: turning away (no face / ears) is held for awayMs, a stranger is not", () => {
  const g = guard()
  look(g, [mp(ME)])
  g.verify(verifyOwner({ faces: [], bodies: [] }), 1000)
  assert.equal(g.decision(1000).hazy, false) // within awayMs of the last ok
  look(g, [mp(ME)], 480, 1000)
  g.verify(verifyOwner({ faces: [], bodies: [] }), 2400)
  look(g, [mp(ME)], 1080, 2400)
  assert.equal(g.decision(2499).hazy, false)
  g.verify(verifyOwner({ faces: [], bodies: [] }), 3000)
  assert.deepEqual(g.decision(3000), { hazy: true, reason: "no_face" })
  const s = guard()
  look(s, [mp(ME)])
  s.verify(verifyOwner({ faces: [face({ similarity: 0.1 })], bodies: ears }), 500)
  assert.deepEqual(s.decision(500), { hazy: true, reason: "not_owner" })
})

test("guard: tuning (awayMs) applies to the gaze delay", () => {
  const g = createGuard({ enrolled: true, awayMs: 5000 })
  g.setCamera({ ok: true })
  g.verify(verifyOwner({ faces: [face()], bodies: ears }), 0)
  look(g, [mp(ME)])
  assert.equal(g.decision(400).hazy, false)
  for (let t = 480; t <= 4000; t += 80) g.gaze([mp(ME, { yaw: 80 })], t)
  g.verify(verifyOwner({ faces: [face()], bodies: ears }), 3900)
  assert.equal(g.decision(4000).hazy, false) // 3.5s away < 5s
  g.setTuning({ awayMs: 1000 })
  g.gaze([mp(ME, { yaw: 80 })], 4080)
  assert.equal(g.decision(4080).reason, "away")
})

test("haze-off allowed when clear, or when the camera/face ID cannot work", () => {
  assert.equal(hazeOffAllowed(false, null), true)
  for (const r of ["error", "frozen", "dark", "not_enrolled"]) assert.equal(hazeOffAllowed(true, r), true)
  for (const r of ["away", "stale", "not_owner", "other_looking"]) assert.equal(hazeOffAllowed(true, r), false)
})

test("haze CSS hides every floating body child and top-layer element, keeps header/main/lock UI", async () => {
  const { readFileSync } = await import("node:fs")
  const css = readFileSync(new URL("../../app/assets/stylesheets/privacy_gaze.css", import.meta.url), "utf8")
  const rule = css.match(/body\[data-privacy-gaze-state="hazy"\] > :not\(([^)]*)\)[^{]*\{([^}]*)\}/)
  assert.ok(rule, "hazy body > :not(...) rule exists")
  for (const keep of ["header.app-header", "main.app-main", ".privacy-stage"]) assert.ok(rule[1].includes(keep), keep)
  for (const hide of ["app-notes-bar", "ask-agent-shell", "shortcuts-shell"]) assert.ok(!rule[1].includes(hide), `${hide} must not be allow-listed`)
  assert.match(css, /dialog\[open\], \[popover\]:popover-open/)
  assert.match(rule[2], /visibility:\s*hidden/)
})
