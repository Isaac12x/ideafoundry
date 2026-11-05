import test from "node:test"
import assert from "node:assert/strict"
import { nearestLine } from "../../app/javascript/lib/kb_ocr_select.mjs"

const lines = [{ x: 10, y: 10, w: 50, h: 5 }, { x: 10, y: 30, w: 50, h: 5 }]

test("above/below all lines clamp to first start / last end", () => {
  assert.deepEqual(nearestLine(lines, 80, 2), { index: 0, side: "before" })
  assert.deepEqual(nearestLine(lines, 5, 90), { index: 1, side: "after" })
})
test("gap between lines picks the nearer one", () => {
  assert.equal(nearestLine(lines, 20, 18).index, 0)
  assert.equal(nearestLine(lines, 20, 27).index, 1)
})
test("x side of the line box", () => {
  assert.equal(nearestLine(lines, 5, 12).side, "before")
  assert.equal(nearestLine(lines, 30, 12).side, "inside")
  assert.equal(nearestLine(lines, 90, 32).side, "after")
})
test("no lines", () => assert.equal(nearestLine([], 1, 1), null))
