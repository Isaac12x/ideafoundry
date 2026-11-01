import test from "node:test"
import assert from "node:assert/strict"
import { inverseScale, clock } from "../../app/javascript/lib/kb_zoom.mjs"

test("inverseScale counters page zoom and pinch, clamped", () => {
  assert.equal(inverseScale(1, 1, 1), 1)
  assert.equal(inverseScale(2, 1, 1), 0.5) // browser zoom 200%
  assert.equal(inverseScale(2, 2, 1), 1) // loaded already zoomed: that is the baseline
  assert.equal(inverseScale(1, 1, 2), 0.5) // pinch
  assert.equal(inverseScale(5, 1, 1), 0.2) // clamp
  assert.equal(inverseScale(NaN, 1, 1), 1)
})

test("clock formats m:ss and h:mm:ss", () => {
  assert.equal(clock(0), "0:00")
  assert.equal(clock(75.9), "1:15")
  assert.equal(clock(3725), "1:02:05")
  assert.equal(clock(NaN), "0:00")
})
