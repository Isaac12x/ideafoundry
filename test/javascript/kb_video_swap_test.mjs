import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { adoptRender, swapTo, swapKey, PLAYER } from "../../app/javascript/lib/kb_video_swap.mjs"

globalThis.CustomEvent ??= class { constructor(type, init) { this.type = type; this.detail = init?.detail } }

const load = async (file, name, ...args) => {
  const src = (await readFile(new URL(`../../app/javascript/controllers/${file}`, import.meta.url), "utf8"))
    .replace(/^import .*$/gm, "").replace("export default class extends Controller", `return class ${name} extends Controller`)
  return new Function("Controller", ...args.map(([k]) => k), src)(class {}, ...args.map(([, v]) => v))
}
const Tree = () => load("kb_tree_controller.js", "T", ["confirmDialog"], ["alertDialog"], ["dropZone"], ["insertNear"], ["shift"], ["embeddedUrl"], ["clipFromUrl"], ["formatClip"], ["PLAYER", PLAYER], ["adoptRender", adoptRender], ["swapKey", swapKey], ["swapTo", swapTo], ["unwarm"], ["warm"])
const Resume = () => load("kb_resume_controller.js", "R")

const el = (classes = []) => { const set = new Set(classes); return { set, classList: { add: (c) => set.add(c), remove: (c) => set.delete(c), contains: (c) => set.has(c) } } }

// A video whose resume controller is real, so swap + undo is exercised end to end.
async function player() {
  const R = await Resume()
  const sources = []
  sources.push({ remove() { sources.splice(sources.indexOf(this), 1) } })
  const media = {
    dataset: {}, paused: false, ended: false, currentTime: 42, readyState: 4, isConnected: true, attrs: { src: null }, sources, played: 0, loads: 0,
    matches: () => true, addEventListener() {}, removeEventListener() {},
    getAttribute(n) { return this.attrs[n] ?? null }, setAttribute(n, v) { this.attrs[n] = v }, removeAttribute(n) { delete this.attrs[n] },
    querySelectorAll() { return [...this.sources] }, append(s) { this.sources.push(s) }, load() { this.loads += 1 }, play() { this.played += 1; return Promise.resolve() },
    set src(v) { this.attrs.src = v },
    dispatchEvent(event) { handler(event); return true }
  }
  let handler
  const store = {}
  globalThis.localStorage = { getItem: (k) => store[k] ?? null, setItem: (k, v) => { store[k] = v } }
  const c = new R()
  Object.assign(c, { keyValue: "0:a.mp4", _media: media, element: media })
  c._key = "kb-resume:0:a.mp4"
  c._listen = c._unlisten = () => {}
  c._onTick = { now() {} }
  handler = (event) => c._swap(event.detail)
  return { media, c, store }
}

function treeWith(Controller, { video, rows }) {
  const t = new Controller()
  globalThis.document = { querySelector: () => video }
  t.element = { querySelectorAll: () => [...rows].filter((r) => r.set.has("is-active")).flatMap((r) => [r, r.link]) }
  return t
}
const row = (rel, classes) => { const r = el(classes); r.link = el(classes.includes("is-active") ? ["is-active"] : []); r.dataset = { kbTreeSrcParam: "0", kbTreeRelParam: rel }; r.querySelector = () => r.link; r.closest = () => r; return r }
const click = (r, url = "/v") => ({ currentTarget: Object.assign(r.link, { dataset: { kbVideo: url }, closest: () => r }), defaultPrevented: false, button: 0 })

test("D2: a click on a missing video restores the old file, position, key and highlight", async () => {
  const Controller = await Tree()
  const { media, c } = await player()
  media.attrs.src = "/old"
  const a = row("a.mp4", ["is-active"]), b = row("b.mp4", ["is-new"])
  const t = treeWith(Controller, { video: media, rows: [a, b] })

  t.markSeen(click(b, "/new"))
  assert.equal(media.attrs.src, "/new")
  assert.equal(c.keyValue, "0:b.mp4")
  assert.ok(!b.set.has("is-new"))

  t._undoSwap() // frame-missing / fetch error / non-OK
  assert.equal(media.attrs.src, "/old")
  assert.equal(c.keyValue, "0:a.mp4")
  assert.equal(media.dataset.kbSwapKey, undefined)
  assert.ok(a.set.has("is-active") && !b.set.has("is-active"))
  assert.ok(b.set.has("is-new"))
  assert.equal(media.sources.length, 1)
})

test("D2: rapid A -> B -> C that fails goes back to A, not the stale B", async () => {
  const Controller = await Tree()
  const { media, c } = await player()
  media.attrs.src = "/a"
  const a = row("a.mp4", ["is-active"]), b = row("b.mp4", []), cc = row("c.mp4", [])
  const t = treeWith(Controller, { video: media, rows: [a, b, cc] })
  t.markSeen(click(b, "/b"))
  t.markSeen(click(cc, "/c"))
  t._undoSwap()
  assert.equal(media.attrs.src, "/a")
  assert.equal(c.keyValue, "0:a.mp4")
  assert.ok(a.set.has("is-active") && !cc.set.has("is-active") && !b.set.has("is-active"))
})

test("D2: a frame that loads keeps the swap (nothing to undo afterwards)", async () => {
  const Controller = await Tree()
  const { media } = await player()
  media.attrs.src = "/a"
  const a = row("a.mp4", ["is-active"]), b = row("b.mp4", [])
  const t = treeWith(Controller, { video: media, rows: [a, b] })
  t.markSeen(click(b, "/b"))
  t._pendingSwap = null // what the frame-load listener does
  t._undoSwap()
  assert.equal(media.attrs.src, "/b")
})

test("D4: a video nobody handles (media editor) is paused, not left playing", async () => {
  const Controller = await Tree()
  let paused = 0
  const video = { dispatchEvent: () => true, pause: () => { paused += 1 } }
  const a = row("a.mp4", ["is-active"]), b = row("b.mp4", [])
  treeWith(Controller, { video, rows: [a, b] }).markSeen(click(b, "/b"))
  assert.equal(paused, 1)
  assert.equal(swapTo(video, { url: "/x", key: "k" }), null)
})

test("D1: adoptRender only touches #kb-content and only when the incoming frame shows the swapped file", () => {
  const live = { dataset: { kbSwapKey: "0:b.mp4" }, attributes: [], querySelectorAll: () => [], replaceWith() {} }
  const incoming = (key) => ({ dataset: { kbResumeKeyValue: key }, attributes: [], querySelectorAll: () => [], replaceWith(node) { this.replacedWith = node } })
  const frame = (id, v) => ({ id, querySelector: () => v })
  const original = () => {}
  const run = (target, next) => { const event = { target, detail: { newFrame: next, render: original } }; adoptRender(event); return event.detail.render }

  assert.equal(run(frame("other", live), frame("x", incoming("0:b.mp4"))), original, "other frames keep Turbo's render")
  assert.equal(run(frame("kb-content", live), frame("x", incoming("0:c.mp4"))), original, "a different file keeps Turbo's render")
  assert.equal(run(frame("kb-content", null), frame("x", incoming("0:b.mp4"))), original, "no live video keeps Turbo's render")

  let turboCalled = 0
  const inc = incoming("0:b.mp4")
  const event = { target: frame("kb-content", live), detail: { newFrame: frame("x", inc), render: () => { turboCalled += 1 } } }
  adoptRender(event)
  assert.notEqual(event.detail.render, original)
  event.detail.render({}, frame("x", inc))
  assert.equal(inc.replacedWith, live)
  assert.equal(turboCalled, 1, "Turbo's own render still runs (scripts, autofocus, scroll)")
})
