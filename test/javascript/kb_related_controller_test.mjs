import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

async function load() {
  const src = await readFile(new URL("../../app/javascript/controllers/kb_related_controller.js", import.meta.url), "utf8")
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", "return class R extends Controller")
  return new Function("Controller", body)(class {})
}

const classes = () => ({ remove() {}, add() {} })

test("Esc ends the drag for good: moving again does not restart it, releasing does not link", async () => {
  const R = await load()
  const c = new R()
  c.liveTarget = {}
  const calls = []
  globalThis.document = { removeEventListener() {}, documentElement: { classList: classes() } }
  globalThis.removeEventListener = () => {}
  globalThis.requestAnimationFrame = () => 1
  c._down = { x: 0, y: 0, id: 1 }
  c._raf = 1
  c._drag = { state: "drag", row: null, dot: { classList: classes() } }
  c.formTarget = { requestSubmit: () => calls.push("submit") }
  c._begin = () => calls.push("begin")

  c._end(false) // what the Escape handler calls

  assert.equal(c._down, null)
  assert.equal(c._drag.state, "retract")
  c.move({ clientX: 100, clientY: 100 })
  c.up()
  assert.deepEqual(calls, [])
})

test("pointercancel while the drawer opens is ignored; a later one ends the drag", async () => {
  const R = await load()
  const c = new R()
  c.liveTarget = {}
  globalThis.document = { removeEventListener() {}, documentElement: { classList: classes() } }
  globalThis.removeEventListener = () => {}
  globalThis.requestAnimationFrame = () => 1
  c._raf = 1
  c._drag = { state: "drag", row: null, opened: performance.now(), dot: { classList: classes() } }

  c._cancelWin() // drawer just opened
  assert.equal(c._drag.state, "drag")
  c.cancelPointer() // element-level lostpointercapture: window listeners own the gesture
  assert.equal(c._drag.state, "drag")

  c._drag.opened = performance.now() - 2000
  c._cancelWin()
  assert.equal(c._drag.state, "retract")
})

test("link mode keys: arrows move, Enter links only an allowed row, Esc exits", async () => {
  const R = await load()
  const c = new R()
  c.liveTarget = {}
  const calls = []
  c._go = (n) => calls.push(`go${n}`)
  c._say = (t) => calls.push(`say:${t}`)
  c._end = (ok) => calls.push(`end${ok}`)
  const ev = (key) => ({ key, defaultPrevented: false, preventDefault() { this.defaultPrevented = true } })
  c._drag = { kb: true, row: {}, denied: false }

  c._keydown(ev("ArrowDown")); c._keydown(ev("ArrowUp"))
  c._keydown(ev("Enter"))
  c._drag.denied = true
  c._keydown(ev("Enter"))
  c._keydown({ ...ev("ArrowDown"), defaultPrevented: true }) // already handled by the handle's own keydown
  c._keydown(ev("Escape"))
  assert.deepEqual(calls, ["go1", "go-1", "endtrue", "say:Already related", "endfalse"])

  c._drag = { kb: false } // pointer drags ignore the arrow keys
  calls.length = 0
  c._keydown(ev("ArrowDown"))
  assert.deepEqual(calls, [])
})
