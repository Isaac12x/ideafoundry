import test from "node:test"
import assert from "node:assert/strict"
import { timeFromPointer, clampLeft, bucketStep, bucketTime } from "../../app/javascript/lib/kb_seek_preview.mjs"

const rect = { left: 100, width: 200 }

test("timeFromPointer maps and clamps to the bar", () => {
  assert.equal(timeFromPointer(200, rect, 60), 30)
  assert.equal(timeFromPointer(50, rect, 60), 0)
  assert.equal(timeFromPointer(999, rect, 60), 60)
  assert.equal(timeFromPointer(200, rect, NaN), 0)
  assert.equal(timeFromPointer(200, { left: 0, width: 0 }, 60), 0)
})

test("clampLeft keeps the thumbnail inside the player", () => {
  assert.equal(clampLeft(300, 160, 600), 220)
  assert.equal(clampLeft(10, 160, 600), 0)
  assert.equal(clampLeft(590, 160, 600), 440)
  assert.equal(clampLeft(50, 160, 100), 0)
})

test("bucketTime groups nearby times", () => {
  assert.equal(bucketStep(30), 0.5)
  assert.equal(bucketStep(3000), 20)
  assert.equal(bucketTime(41.9, 20), 40)
  assert.equal(bucketTime(0.2, 0.5), 0)
})

// Controller behaviour with stubbed DOM: stale dimming, prefill ordering, abort on source change.
import { readFile } from "node:fs/promises"
const loadPreview = async () => {
  const src = (await readFile(new URL("../../app/javascript/controllers/kb_seek_preview_controller.js", import.meta.url), "utf8"))
    .replace(/^import .*$/gm, "").replace("export default class extends Controller", "return class extends Controller")
  const lib = await import("../../app/javascript/lib/kb_seek_preview.mjs")
  return new Function("Controller", "clock", "timeFromPointer", "clampLeft", "bucketStep", "bucketTime", src)(class {}, (t) => String(t), lib.timeFromPointer, lib.clampLeft, lib.bucketStep, lib.bucketTime)
}
const stubController = async () => {
  const C = await loadPreview()
  const c = new C()
  const attrs = new Set()
  const ctx = { drawImage() {} }
  Object.assign(c, {
    _cache: new Map(), _coarse: new Map(), hasThumbTarget: true,
    thumbTarget: { hidden: false, toggleAttribute: (n, on) => (on ? attrs.add(n) : attrs.delete(n)) },
    canvasTarget: { width: 160, height: 90, getContext: () => ctx },
    videoTarget: { duration: 60 }, seekTarget: { style: { setProperty() {}, removeProperty() {} } }
  })
  return { c, attrs }
}

test("a nearest-frame draw is dimmed (data-stale); the exact frame clears it", async () => {
  const { c, attrs } = await stubController()
  c._coarse.set(10, {})
  c.drawNearest(12)
  assert.ok(attrs.has("data-stale"))
  c.draw({}, true)
  assert.ok(!attrs.has("data-stale"))
  const empty = (await stubController())
  empty.c.drawNearest(5) // nothing known yet: blank canvas, still marked as not-this-time
  assert.ok(empty.attrs.has("data-stale"))
})

test("the hovered bucket is decoded before idle prefill; prefill runs when nothing is wanted", async () => {
  const { c } = await stubController()
  const seeks = []
  c._probe = { readyState: 4, currentTime: 0, set t(v) {} }
  Object.defineProperty(c._probe, "currentTime", { get: () => 0, set: (v) => seeks.push(v) })
  c.planCoarse()
  assert.equal(c._todo.length, 24)
  c._wanted = 30
  c.pump()
  assert.deepEqual(seeks, [30])
  c._seeking = null; c._wanted = null
  c.pump()
  assert.equal(seeks.length, 2)
  assert.ok(c._fill)
})

test("source change aborts: probe removed, prefill list and caches dropped", async () => {
  const { c } = await stubController()
  let removed = 0
  c._probe = { removeAttribute() {}, load() {}, remove: () => { removed += 1 } }
  c._todo = [1, 2]; c._cache.set(1, {}); c._coarse.set(2, {})
  c.reset()
  assert.equal(removed, 1)
  assert.equal(c._probe, null)
  assert.equal(c._todo, null)
  assert.equal(c._cache.size + c._coarse.size, 0)
})
