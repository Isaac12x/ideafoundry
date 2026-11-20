import test from "node:test"
import assert from "node:assert/strict"
import { findMatches, stepIndex } from "../../app/javascript/lib/find_bar.mjs"

test("finds every match per node, case-insensitive by default", () => {
  const m = findMatches(["Foo foo", "none", "FOO"], "foo")
  assert.deepEqual(m, [{ node: 0, start: 0, end: 3 }, { node: 0, start: 4, end: 7 }, { node: 2, start: 0, end: 3 }])
})

test("match case and empty query", () => {
  assert.equal(findMatches(["Foo foo"], "foo", true).length, 1)
  assert.deepEqual(findMatches(["abc"], ""), [])
})

test("matches do not overlap", () => {
  assert.equal(findMatches(["aaaa"], "aa").length, 2)
})

test("stepIndex wraps both ways and handles no matches", () => {
  assert.equal(stepIndex(2, 1, 3), 0)
  assert.equal(stepIndex(0, -1, 3), 2)
  assert.equal(stepIndex(-1, 1, 0), -1)
})
