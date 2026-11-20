import test from "node:test"
import assert from "node:assert/strict"
import { initialState, enter, back, setMode, parseQuery, canEnter, actionRows, minChars, DEBOUNCE_MS } from "../../app/javascript/lib/palette_state.mjs"

const item = { title: "Idea", actions: [{ label: "Open" }] }

test("right arrow drills into actions only for items that have them", () => {
  const s = initialState()
  assert.equal(canEnter(s, { title: "x" }), false)
  const e = enter(s, { query: "ide", index: 2, item, groups: [] })
  assert.equal(e.level, 1)
  assert.equal(enter(e, { query: "", index: 0, item }), e) // no nesting
  assert.equal(enter(s, { query: "x", index: 0, item: { title: "x" } }), s)
})

test("left restores query and highlighted index", () => {
  const e = enter(initialState(), { query: "ide", index: 3, item, groups: ["g"] })
  const b = back(e)
  assert.deepEqual([b.state.level, b.query, b.index, b.groups], [0, "ide", 3, ["g"]])
  assert.equal(back(b.state), null)
})

test("> means commands only", () => {
  assert.deepEqual(parseQuery("> lock "), { commandsOnly: true, text: "lock" })
  assert.deepEqual(parseQuery(">"), { commandsOnly: true, text: "" })
  assert.deepEqual(parseQuery(" ideas"), { commandsOnly: false, text: "ideas" })
})

test("mode switching leaves drill-in and ignores unknown modes", () => {
  const e = enter(initialState(), { query: "a", index: 0, item })
  const s = setMode(e, "deep")
  assert.deepEqual([s.mode, s.level, s.saved], ["deep", 0, null])
  assert.equal(setMode(s, "bogus").mode, "deep")
})

test("server search is debounced and gated by length", () => {
  assert.ok(DEBOUNCE_MS >= 200)
  assert.equal(minChars("deep"), 3)
  assert.equal(minChars("similar"), 3)
  assert.equal(minChars("quick"), 2)
})

test("action rows render server labels as titles and filter by query", () => {
  const it = { actions: [{ label: "Open", url: "/a" }, { label: "Find similar", run: "similar" }] }
  assert.deepEqual(actionRows(it).map((r) => r.title), ["Open", "Find similar"])
  assert.deepEqual(actionRows(it, "sim").map((r) => r.title), ["Find similar"])
  assert.equal(actionRows(it)[0].url, "/a")
})
