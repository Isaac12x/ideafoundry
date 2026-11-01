import test from "node:test"
import assert from "node:assert/strict"
import { clampMenu, nextIndex, quoteAfterSelection, selectionPrompt } from "../../app/javascript/lib/kb_selection_menu.mjs"

test("prompt quotes every line and names the file; expand asks for depth, ask stays open", () => {
  const expand = selectionPrompt("expand", "a\nb", "n.md")
  assert.match(expand, /^Expand on this passage \(from n\.md\)/)
  assert.ok(expand.includes("> a\n> b"))
  assert.match(selectionPrompt("ask", "x", ""), /^About this passage:\n\n> x\n\n$/)
})

test("menu stays inside the viewport", () => {
  assert.deepEqual(clampMenu(990, 790, 200, 100, 1000, 800), { left: 792, top: 692 })
  assert.deepEqual(clampMenu(-5, 2, 200, 100, 1000, 800), { left: 8, top: 8 })
})

test("arrow focus wraps", () => {
  assert.equal(nextIndex("ArrowDown", 2, 3), 0)
  assert.equal(nextIndex("ArrowUp", 0, 3), 2)
  assert.equal(nextIndex("End", 0, 3), 2)
})

test("quote insert goes after the selection and moves the caret past it", () => {
  const { value, caret } = quoteAfterSelection("one two three", 4, 7)
  assert.equal(value, "one two\n\n> two\n three")
  assert.equal(value.slice(caret), " three")
})

test("opening the menu repeatedly never stacks window blur listeners; close removes it", async () => {
  const { readFile } = await import("node:fs/promises")
  const src = (await readFile(new URL("../../app/javascript/controllers/kb_selection_menu_controller.js", import.meta.url), "utf8"))
    .replace(/^import .*$/gm, "").replace("export default class extends Controller", "return class extends Controller")
  const Menu = new Function("Controller", "clampMenu", "fieldSelection", "nextIndex", "quoteAfterSelection", "selectionPrompt", src)(class {}, () => ({ left: 0, top: 0 }), () => "picked", () => 0, () => ({}), () => "")
  const blurs = []
  const noop = () => {}
  globalThis.window = { addEventListener: (t, f) => t === "blur" && blurs.push(f), removeEventListener: (t, f) => { if (t === "blur") blurs.splice(0, blurs.length, ...blurs.filter((x) => x !== f)) }, innerWidth: 800, innerHeight: 600 }
  globalThis.document = { addEventListener: noop, removeEventListener: noop, activeElement: null, body: { appendChild: noop } }
  const c = new Menu()
  c.element = { addEventListener: noop }
  c.application = { getControllerForElementAndIdentifier: () => null }
  c.build = () => { c.menu = { remove: noop, contains: () => false, getBoundingClientRect: () => ({ width: 1, height: 1 }), style: {}, querySelectorAll: () => [] } }
  c.connect()
  const event = { target: { closest: (s) => (s === "textarea" ? {} : null) }, preventDefault: noop, clientX: 0, clientY: 0 }
  for (let i = 0; i < 4; i++) c.open(event)
  assert.equal(blurs.length, 1)
  c.close(false)
  assert.equal(blurs.length, 0)
  delete globalThis.window; delete globalThis.document
})
