import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

// field_draft.mjs imports "lib/..." (importmap); point it at the real file for node.
const store = new URL("../../app/javascript/lib/idea_draft_store.mjs", import.meta.url).href
const source = (await readFile(new URL("../../app/javascript/lib/field_draft.mjs", import.meta.url), "utf8")).replace('"lib/idea_draft_store"', JSON.stringify(store))
const { saveFieldDraft, restoreFieldDraft, hasFieldDraft, clearFieldDraft } = await import(`data:text/javascript,${encodeURIComponent(source)}`)

const data = new Map()
globalThis.localStorage = { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => data.set(k, v), removeItem: (k) => data.delete(k) }
globalThis.location = { pathname: "/knowledge-base", search: "?src=0" }
globalThis.document = { body: { dataset: { draftUser: "1", draftSeed: "seed" } } }
globalThis.Event = class { constructor(type) { this.type = type } }
const field = (value = "") => ({ name: "text", value, defaultValue: "", form: null, dispatchEvent() {} })

test("a typed draft is stored encrypted, restored into an untouched field, and cleared", async () => {
  await saveFieldDraft(field("secret thoughts"))
  assert.ok(![...data.values()].some((v) => v.includes("secret thoughts")))
  assert.ok(hasFieldDraft(field()))

  const fresh = field()
  assert.equal(await restoreFieldDraft(fresh), true)
  assert.equal(fresh.value, "secret thoughts")

  assert.equal(await restoreFieldDraft(field("typed since")), false) // never overwrite new typing
  clearFieldDraft(field())
  assert.equal(hasFieldDraft(field()), false)
})

test("emptying the field drops the draft; another seed cannot read it", async () => {
  await saveFieldDraft(field("abc"))
  document.body.dataset.draftSeed = "other"
  assert.equal(await restoreFieldDraft(field()), false)
  document.body.dataset.draftSeed = "seed"
  await saveFieldDraft(field(""))
  assert.equal(hasFieldDraft(field()), false)
})
