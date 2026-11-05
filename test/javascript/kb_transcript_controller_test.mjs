import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

async function loadController(window = { getSelection: () => ({ isCollapsed: true }) }) {
  const source = await readFile(new URL("../../app/javascript/controllers/kb_transcript_controller.js", import.meta.url), "utf8")
  const runnable = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbTranscriptController extends Controller")
  return new Function("Controller", "window", "document", runnable)(class {}, window, undefined)
}

function rows(count) {
  const classes = new Set()
  const children = Array.from({ length: count }, () => ({
    offsetTop: 0, offsetHeight: 10,
    classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c) },
    setAttribute() {}, removeAttribute() {}
  }))
  return { children, classes }
}

test("highlight lights the last cue that has started and clears the previous one", async () => {
  const Controller = await loadController()
  const c = new Controller()
  const list = rows(3)
  c.cues = [{ start: 0, end: 5, text: "a" }, { start: 5, end: 9, text: "b" }, { start: 9, end: 12, text: "c" }]
  c.active = -1
  c.hasMediaTarget = true
  c.mediaTarget = { currentTime: 6 }
  c.listTarget = { children: list.children, scrollTop: 0, clientHeight: 100 }

  c.highlight()
  assert.equal(c.active, 1)
  assert.ok(list.classes.has("is-active"))

  c.mediaTarget.currentTime = 10
  c.highlight()
  assert.equal(c.active, 2)
  assert.equal(list.classes.size, 1)

  c.mediaTarget.currentTime = 0
  c.highlight()
  assert.equal(c.active, 0)
})

test("clicking a line seeks, but not while text is being selected", async () => {
  let collapsed = true
  const Controller = await loadController({ getSelection: () => ({ isCollapsed: collapsed }) })
  const c = new Controller()
  let played = 0
  c.cues = [{ start: 0, text: "a" }, { start: 42, text: "b" }]
  c.hasMediaTarget = true
  c.mediaTarget = { currentTime: 0, play() { played += 1 } }

  collapsed = false
  c.seek({ currentTarget: { dataset: { index: "1" } } })
  assert.equal(c.mediaTarget.currentTime, 0)

  collapsed = true
  c.seek({ currentTarget: { dataset: { index: "1" } } })
  assert.equal(c.mediaTarget.currentTime, 42)
  assert.equal(played, 1)
})

test("Enter/Space on a row seeks even with a stale selection, and the active row gets aria-current", async () => {
  const Controller = await loadController({ getSelection: () => ({ isCollapsed: false }) })
  const c = new Controller()
  c.cues = [{ start: 0, text: "a" }, { start: 7, text: "b" }]
  c.hasMediaTarget = true
  c.mediaTarget = { currentTime: 0, play() {} }
  let prevented = false
  c.seek({ type: "keydown", preventDefault: () => { prevented = true }, currentTarget: { dataset: { index: "1" } } })
  assert.equal(c.mediaTarget.currentTime, 7)
  assert.ok(prevented)

  const attrs = new Map()
  const row = { offsetTop: 0, offsetHeight: 10, classList: { add() {}, remove() {} },
    setAttribute: (k, v) => attrs.set(k, v), removeAttribute: (k) => attrs.delete(k) }
  c.active = -1
  c.listTarget = { children: [row, row], scrollTop: 0, clientHeight: 100 }
  c.mediaTarget.currentTime = 1
  c.highlight()
  assert.equal(attrs.get("aria-current"), "true")
})
