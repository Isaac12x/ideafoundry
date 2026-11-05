import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const FormStub = class {}

// Loads the controller with field_draft stubbed, recording what it saved and cleared.
async function load() {
  const source = await readFile(new URL("../../app/javascript/controllers/draft_keeper_controller.js", import.meta.url), "utf8")
  const runnable = source
    .replace(/import \{ Controller \}.*\n/, "")
    .replace(/import \{ clearFieldDraft.*\n/, "")
    .replace("export default class extends Controller", "return class DraftKeeper extends Controller")
  const log = { saved: [], cleared: [] }
  const stubs = {
    clearFieldDraft: (f) => log.cleared.push(f), draftKey: (f) => f.name, restoreFieldDraft: async () => false,
    saveFieldDraft: async (f) => { await null; log.saved.push(f) }
  }
  const Controller = new Function("Controller", ...Object.keys(stubs), "HTMLFormElement", runnable)(class {}, ...Object.values(stubs), FormStub)
  return { Controller, log }
}

test("flush waits for pending drafts to be written", async () => {
  const { Controller, log } = await load()
  const keeper = new Controller()
  keeper.timers = new Map([[{ name: "a" }, setTimeout(() => {}, 1e6)], [{ name: "b" }, setTimeout(() => {}, 1e6)]])
  keeper.save = function (field) { this.timers.delete(field); return Promise.resolve().then(() => log.saved.push(field)) }
  await keeper.flush()
  assert.equal(log.saved.length, 2)
  assert.equal(keeper.timers.size, 0)
})

test("a rejected save keeps the draft; only a successful turbo submit clears it", async () => {
  const { Controller, log } = await load()
  const handlers = {}
  const target = { addEventListener: (type, fn) => { handlers[type] = fn }, removeEventListener() {}, querySelectorAll: () => [], visibilityState: "visible" }
  Object.assign(globalThis, { document: target, window: target, location: { pathname: "/knowledge-base" } })
  const Keeper = class extends Controller { constructor() { super(); this.timers = new Map() } }
  const keeper = new Keeper()
  keeper.connect()

  const field = { name: "text", matches: () => true, closest: () => null }
  const form = new FormStub()
  form.querySelectorAll = () => [field]
  handlers["turbo:submit-end"]({ detail: { success: false }, target: form })
  assert.equal(log.cleared.length, 0)
  handlers["turbo:submit-end"]({ detail: { success: true }, target: form })
  assert.equal(log.cleared.length, 1)
})
