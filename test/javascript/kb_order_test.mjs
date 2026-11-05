import test from "node:test"
import assert from "node:assert/strict"
import { dropZone, insertNear, shift } from "../../app/javascript/lib/kb_order.mjs"

test("dropZone: folders get a middle band to drop into, files split in halves", () => {
  assert.equal(dropZone(2, 20, true), "before")
  assert.equal(dropZone(10, 20, true), "into")
  assert.equal(dropZone(18, 20, true), "after")
  assert.equal(dropZone(4, 20, false), "before")
  assert.equal(dropZone(15, 20, false), "after")
})

test("insertNear moves a name next to its target and never duplicates it", () => {
  assert.deepEqual(insertNear(["a", "b", "c"], "a", "c", "after"), ["b", "c", "a"])
  assert.deepEqual(insertNear(["a", "b", "c"], "c", "a", "before"), ["c", "a", "b"])
  assert.deepEqual(insertNear(["a", "b"], "z", "b", "before"), ["a", "z", "b"])
  assert.deepEqual(insertNear(["a", "b"], "z", "nope", "after"), ["a", "b", "z"])
})

test("shift steps one place and refuses to fall off the ends", () => {
  assert.deepEqual(shift(["a", "b", "c"], "b", -1), ["b", "a", "c"])
  assert.deepEqual(shift(["a", "b", "c"], "b", 1), ["a", "c", "b"])
  assert.equal(shift(["a", "b"], "a", -1), null)
  assert.equal(shift(["a", "b"], "b", 1), null)
  assert.equal(shift(["a"], "q", 1), null)
})
