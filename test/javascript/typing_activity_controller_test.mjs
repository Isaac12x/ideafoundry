import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const bindings = await import("../../app/javascript/lib/shortcut_bindings.mjs")
const source = await readFile(new URL("../../app/javascript/controllers/typing_activity_controller.js", import.meta.url), "utf8")
const Typing = new Function("Controller", "binding", "matches", source
  .replace(/^import .*\n/gm, "")
  .replace("export default class extends Controller", "return class extends Controller"))(class {}, bindings.binding, bindings.matches)

// Minimal DOM: records order of effects so "cover before any network" is assertable.
function setup({ fetchImpl } = {}) {
  const log = []
  const media = { pause: () => log.push("pause") }
  const dialog = { close: () => log.push("dialog.close") }
  const root = { children: [], appendChild(el) { this.children.push(el); log.push("cover") } }
  const keyListeners = []
  globalThis.document = {
    body: { dataset: {}, inert: false },
    documentElement: root,
    activeElement: { blur: () => log.push("blur") },
    createElement: () => ({ style: {}, kids: [], attrs: {}, setAttribute(k, v) { this.attrs[k] = v }, appendChild(el) { this.kids.push(el); this.firstChild = this.kids[0] }, remove() {} }),
    getElementById: (id) => root.children.find((el) => el.id === id) || null,
    querySelector: () => null,
    querySelectorAll: (sel) => (sel === "video, audio" ? [media] : sel === "dialog[open]" ? [dialog] : []),
    dispatchEvent: () => log.push("draft:flush"),
    addEventListener: (type) => log.push(`doc:${type}`),
  }
  const online = []
  globalThis.window = { __online: online, addEventListener: (type, fn) => (type === "keydown" ? keyListeners.push(fn) : type === "online" && online.push(fn)), removeEventListener() {}, location: { replace: (u) => log.push(`replace:${u}`) }, scrollY: 0 }
  globalThis.CustomEvent = class { constructor(type, init) { this.type = type; this.detail = init?.detail } }
  globalThis.fetch = (...args) => { log.push("fetch"); return fetchImpl(...args) }
  const c = new Typing()
  Object.assign(c, { hasLockActionUrlValue: true, lockActionUrlValue: "/typing-lock/lock", lockUrlValue: "/", timeoutMs: 60_000, lastActivityAt: Date.now(), locked: false })
  c.csrfToken = () => "t"
  c.hideAskAgent = () => log.push("hideAskAgent")
  c.submitLockAction = () => log.push("fallback-post")
  return { c, log, keyListeners }
}
const teardown = () => { for (const k of ["document", "window", "fetch", "CustomEvent"]) delete globalThis[k]; Object.defineProperty(globalThis, "navigator", { value: { onLine: true }, configurable: true }) }
const offline = (on) => Object.defineProperty(globalThis, "navigator", { value: { onLine: !on }, configurable: true })
const tick = () => new Promise((resolve) => setTimeout(resolve, 20))

test("lock covers and pauses media synchronously, before any network request", async () => {
  const { c, log, keyListeners } = setup({ fetchImpl: async () => ({ type: "opaqueredirect", ok: false }) })
  c.lock()
  assert.ok(!log.includes("fetch") || log.indexOf("cover") < log.indexOf("fetch"))
  assert.deepEqual(log.slice(0, 5).filter((e) => ["cover", "pause", "dialog.close"].includes(e)).sort(), ["cover", "dialog.close", "pause"])
  assert.equal(document.body.inert, true)
  assert.equal(keyListeners.length, 1)
  await tick()
  assert.ok(log.includes("replace:/"))
  assert.ok(log.indexOf("cover") < log.indexOf("replace:/"))
  teardown()
})

test("offline: the cover shows a quiet label, keeps retrying with backoff, never reveals, and finishes when back online", async () => {
  let calls = 0
  let up = false
  const { c, log } = setup({ fetchImpl: async () => { calls += 1; if (!up) throw new Error("offline"); return { type: "opaqueredirect", ok: false } } })
  offline(true)
  c.backoffBaseMs = 5
  c.lock()
  await new Promise((resolve) => setTimeout(resolve, 1500))
  assert.ok(calls > 3, `kept retrying past the quick attempts (${calls})`)
  const cover = document.getElementById("typing-lock-cover")
  assert.equal(cover.firstChild.textContent, "Locked. Offline, retrying")
  assert.equal(cover.attrs["aria-label"], "Locked. Offline, retrying")
  assert.notEqual(cover.style.cursor, "wait")
  assert.ok(!log.some((e) => e.startsWith("replace:")) && document.body.inert)
  assert.ok(!log.includes("fallback-post"), "offline a form post would swap the cover for the browser error page")
  up = true
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.ok(log.includes("replace:/"))
  teardown()
})

test("offline: an online event retries at once instead of waiting out the backoff", async () => {
  let calls = 0
  const { c, log } = setup({ fetchImpl: async () => { calls += 1; if (calls <= 3) throw new Error("offline"); return { type: "opaqueredirect", ok: false } } })
  c.backoffBaseMs = 60_000
  c.lock()
  await new Promise((resolve) => setTimeout(resolve, 1500))
  assert.equal(calls, 3)
  window.__online.forEach((fn) => fn())
  await tick()
  assert.ok(log.includes("replace:/"))
  teardown()
})

test("quick attempts failing: a plain form post is tried, the cover stays, and retrying continues until the lock lands", async () => {
  let calls = 0
  let ok = false
  const { c, log } = setup({ fetchImpl: async () => { calls += 1; return ok ? { type: "opaqueredirect", ok: false } : { type: "basic", ok: false, status: 422 } } })
  c.backoffBaseMs = 5
  c.lock()
  await new Promise((resolve) => setTimeout(resolve, 1500))
  assert.ok(calls >= 3)
  assert.equal(log.filter((e) => e === "fallback-post").length, 1)
  assert.ok(document.getElementById("typing-lock-cover"))
  assert.equal(document.getElementById("typing-lock-cover").firstChild, undefined, "a server answer is not 'offline': no offline label")
  ok = true
  window.__online.forEach((fn) => fn())
  await tick()
  assert.ok(log.includes("replace:/"))
  teardown()
})

test("leave() waits for drafts at most ~300ms", async () => {
  const { c } = setup({ fetchImpl: async () => ({ ok: true }) })
  document.dispatchEvent = (event) => event.detail.wait.push(new Promise(() => {})) // a flush that never settles
  globalThis.sessionStorage = { setItem() {} }
  const started = Date.now()
  await c.leave()
  const took = Date.now() - started
  assert.ok(took >= 250 && took < 600, `took ${took}ms`)
  delete globalThis.sessionStorage
  teardown()
})

test("lock is idempotent", async () => {
  const { c, log } = setup({ fetchImpl: async () => ({ ok: true }) })
  c.lock(); c.lock()
  assert.equal(log.filter((e) => e === "cover").length, 1)
  await tick()
  teardown()
})

test("checkDeadline locks an overdue tab at once and leaves a fresh one alone", async () => {
  const { c, log } = setup({ fetchImpl: async () => ({ ok: true }) })
  c.checkDeadline()
  assert.ok(!log.includes("cover"))
  c.lastActivityAt = Date.now() - 61_000
  c.checkDeadline()
  assert.ok(log.includes("cover"))
  await tick()
  teardown()
})

test("bfcache restore while locked finishes the lock instead of revealing content", async () => {
  const { c, log } = setup({ fetchImpl: async () => ({ ok: true }) })
  c.lock()
  await tick()
  log.length = 0
  c.checkDeadline({ persisted: true })
  assert.ok(log.includes("replace:/"))
  teardown()
})

test("the shortcut listener is registered in capture phase and Ctrl/Cmd+S never locks", () => {
  assert.match(source, /addEventListener\("keydown", this\.boundHandleShortcut, true\)/)
  const { c } = setup({ fetchImpl: async () => ({ ok: true }) })
  assert.equal(c.isLockShortcut({ key: "s", ctrlKey: true, metaKey: false, altKey: false, shiftKey: false }), false)
  teardown()
})

test("once covered, Turbo visits and renders are cancelled so nothing swaps in under the cover", async () => {
  const { c, log } = setup({ fetchImpl: async () => ({ type: "opaqueredirect", ok: false }) })
  c.lock()
  await tick()
  for (const type of ["turbo:before-visit", "turbo:before-render", "turbo:before-frame-render"]) assert.ok(log.includes(`doc:${type}`), type)
  teardown()
})

test("a lock chord buffered while the page loaded locks as soon as the controller exists; Ctrl+S in the buffer does not", async () => {
  const { c, log } = setup({ fetchImpl: async () => ({ type: "opaqueredirect", ok: false }) })
  window.__earlyKeys = [{ key: "s", code: "KeyS", ctrlKey: true, metaKey: false, altKey: false, shiftKey: false }]
  c.replayEarlyKeys()
  assert.ok(!log.includes("cover"))
  assert.equal(window.__earlyKeys, null)
  const mac = bindings.isMac()
  window.__earlyKeys = [{ key: "l", code: "KeyL", ctrlKey: mac, metaKey: false, altKey: !mac, shiftKey: false }]
  c.replayEarlyKeys()
  assert.ok(log.includes("cover"))
  await tick()
  teardown()
})
