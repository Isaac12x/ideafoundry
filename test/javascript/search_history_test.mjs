import test from "node:test"
import assert from "node:assert/strict"
import { topSearches, recordSearch, clearSearches } from "../../app/javascript/lib/search_history.mjs"
import { emojiMatches } from "../../app/javascript/lib/emoji_grid.mjs"

const memory = () => { const m = new Map(); return { getItem: (k) => m.get(k) ?? null, setItem: (k, v) => m.set(k, v), removeItem: (k) => m.delete(k) } }

test("top searches rank by frequency then recency, capped at 5", () => {
  const s = memory()
  "abcdefg".split("").forEach((q, i) => recordSearch(s, q, i))
  assert.deepEqual(topSearches(s), ["g", "f", "e", "d", "c"])
  recordSearch(s, "a", 100); recordSearch(s, " a ", 101)
  assert.deepEqual(topSearches(s).slice(0, 2), ["a", "g"])
})

test("blank queries ignored, clear empties, broken storage is safe", () => {
  const s = memory()
  recordSearch(s, "  ")
  assert.deepEqual(topSearches(s), [])
  recordSearch(s, "x"); clearSearches(s)
  assert.deepEqual(topSearches(s), [])
  const bad = { getItem() { throw new Error("no") }, setItem() { throw new Error("no") }, removeItem() { throw new Error("no") } }
  recordSearch(bad, "x"); clearSearches(bad)
  assert.deepEqual(topSearches(bad), [])
})

test("emoji search matches partial, case-insensitive, any term in name or keywords", () => {
  const hay = "thumbs up approve like yes"
  assert.ok(emojiMatches(hay, "THUMB"))
  assert.ok(emojiMatches(hay, "approve up"))
  assert.ok(emojiMatches(hay, ""))
  assert.ok(!emojiMatches(hay, "down"))
})
