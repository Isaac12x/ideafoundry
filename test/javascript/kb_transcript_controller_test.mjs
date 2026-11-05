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

test("karaoke: fills words by length across the cue, falls back to next start for a missing end, centers the row", async () => {
  const Controller = await loadController({ getSelection: () => ({ isCollapsed: true }), matchMedia: () => ({ matches: false }) })
  const c = new Controller()
  const vars = []
  const words = ["ab", "cdef"].map((text, i) => ({ textContent: text, dataset: {}, style: { setProperty: (_k, v) => { vars[i] = v } } }))
  const row = { offsetTop: 200, offsetHeight: 20, classList: { add() {}, remove() {} }, setAttribute() {}, removeAttribute() {},
    querySelectorAll: () => words }
  let scroll
  c.cues = [{ start: 10, end: 16, text: "ab cdef" }, { start: 20, text: "next" }]
  c.active = -1
  c.hasMediaTarget = true
  c.mediaTarget = { currentTime: 11 } 
  c.listTarget = { children: [row, row], scrollTop: 0, clientHeight: 100, scrollTo: (o) => { scroll = o } }

  c.highlight()
  assert.deepEqual(vars, [0.5, 0]) // 1/6 * 6 chars = 1 char: half of "ab"
  assert.deepEqual(scroll, { top: 200 - 40, behavior: "smooth" })

  c.mediaTarget.currentTime = 13
  c.highlight()
  assert.deepEqual(vars, [1, 0.25])

  c.mediaTarget.currentTime = 16 // at the end: fully filled
  c.highlight()
  assert.deepEqual(vars, [1, 1])

  c.mediaTarget.currentTime = 22 // no end: runs to start + 5
  c.highlight()
  assert.equal(c.active, 1)

  c.userAt = Date.now() // manual scroll: no auto-centering for a moment
  scroll = null
  c.mediaTarget.currentTime = 10
  c.highlight()
  assert.equal(scroll, null)
})

function setup(window = { getSelection: () => ({ isCollapsed: true }) }) {
  return loadController(window).then((Controller) => {
    const c = new Controller()
    const list = rows(3)
    const scrolls = []
    c.cues = [{ start: 0, end: 4, text: "a" }, { start: 10, end: 14, text: "b" }, { start: 20, end: 24, text: "c" }]
    c.active = -1
    c.hasMediaTarget = true
    c.mediaTarget = { currentTime: 1, play() {} }
    c.listTarget = { children: list.children, clientHeight: 100, scrollTo: (o) => scrolls.push(o) }
    return { c, list, scrolls }
  })
}

test("a finished cue goes grey in a gap and the next lights at its start", async () => {
  const { c, list } = await setup()
  c.highlight()
  assert.equal(c.active, 0)
  c.mediaTarget.currentTime = 6 // after cue 0 ended, before cue 1
  c.highlight()
  assert.equal(c.active, -1)
  assert.equal(list.classes.size, 0)
  c.mediaTarget.currentTime = 10
  c.highlight()
  assert.equal(c.active, 1)
  c.mediaTarget.currentTime = 30 // past the last cue
  c.highlight()
  assert.equal(c.active, -1)
})

test("seeking recenters right after a manual scroll, instantly; normal advance is smooth", async () => {
  const { c, scrolls } = await setup()
  c.highlight()
  c.mediaTarget.currentTime = 10
  c.highlight()
  assert.equal(scrolls.at(-1).behavior, "smooth")
  c.userAt = Date.now()
  scrolls.length = 0
  c.mediaTarget.currentTime = 12
  c.seek({ currentTarget: { dataset: { index: "2" } } }) // userAt reset, jump flagged
  c.mediaTarget.currentTime = 20
  c.highlight()
  assert.equal(scrolls.length, 1)
  assert.equal(scrolls[0].behavior, "auto")
})

test("a hidden (zero-height) list never scrolls; resizing recenters; idle timer recenters after manual scroll", async () => {
  const { c, scrolls } = await setup()
  c.listTarget.clientHeight = 0
  c.highlight()
  assert.equal(scrolls.length, 0)
  c.listTarget.clientHeight = 100
  c.recenter("auto")
  assert.equal(scrolls.length, 1)
})
