import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("shortcut hint keys are deterministic and compact", async () => {
  const ShortcutsController = await loadShortcutsController();

  assert.equal(ShortcutsController.hintForIndex(0), "a");
  assert.equal(ShortcutsController.hintForIndex(1), "s");
  assert.equal(ShortcutsController.hintForIndex(35), "0");
  assert.equal(ShortcutsController.hintForIndex(36), "aa");
  assert.equal(ShortcutsController.hintForIndex(37), "as");
});

test("shortcut labels are normalized for cheatsheet display", async () => {
  const ShortcutsController = await loadShortcutsController();
  const controller = new ShortcutsController();

  assert.equal(controller.cleanLabel("  Save\n\nCurrent\tIdea  "), "Save Current Idea");
});

const key = (init) => ({ key: "", metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, preventDefault() { this.prevented = true }, ...init })

// querySelector returns the control only when one of the selector's parts is exactly `match`.
function clickSpy(match = "button[type='submit']") {
  const control = { clicks: 0, click() { this.clicks += 1 } }
  const querySelector = (selector) => (selector.split(",").some((part) => part.trim() === match) ? control : null)
  return { control, form: { closest: () => null, querySelector } }
}

// A data-shortcut-skip lock form (header Lock button / KB project lock panel) plus a page form;
// firstVisible honours the :not([data-shortcut-skip]) exclusion it is given.
async function controllerWithLockForm({ pageForm = null } = {}) {
  const ShortcutsController = await loadShortcutsController()
  const controller = new ShortcutsController()
  const lock = clickSpy()
  lock.form.closest = (selector) => (selector === "[data-shortcut-skip]" ? {} : null)
  controller.firstVisible = (selector) => (selector.includes(":not([data-shortcut-skip])") ? pageForm : lock.form)
  controller.clickFirst = () => false
  return { controller, lock }
}

test("Ctrl/Cmd+S outside any form never submits the lock form", async () => {
  const { controller, lock } = await controllerWithLockForm()
  const event = key({ key: "s", ctrlKey: true, target: { closest: () => null } })

  assert.equal(controller.handleComboShortcut(event), true)
  assert.equal(event.prevented, true)
  assert.equal(lock.control.clicks, 0)
})

test("Ctrl/Cmd+S with the KB project lock panel visible in main does not submit it", async () => {
  const { controller, lock } = await controllerWithLockForm()
  lock.form.requestSubmit = () => { lock.control.clicks += 1 }
  const selectors = []
  const firstVisible = controller.firstVisible
  controller.firstVisible = (selector) => { selectors.push(selector); return firstVisible(selector) }
  controller.clickFirst = (selector) => { selectors.push(selector); return false }

  controller.handleComboShortcut(key({ key: "s", ctrlKey: true, target: { closest: () => null } }))
  controller.handleComboShortcut(key({ key: "Enter", ctrlKey: true, target: { closest: () => null } }))
  assert.equal(lock.control.clicks, 0)
  // Every fallback lookup must exclude lock forms, else a real DOM would find the panel.
  assert.ok(selectors.length >= 2 && selectors.every((selector) => selector.includes("[data-shortcut-skip]")), selectors.join(" | "))
})

test("a bare key with nothing to act on is not swallowed", async () => {
  const { controller } = await controllerWithLockForm()
  globalThis.document = { body: { dataset: {} }, querySelector: () => null }
  globalThis.Element = class {}
  const event = key({ key: "e", target: { closest: () => null } })

  assert.equal(controller.handleComboShortcut(event), false)
  assert.equal(event.prevented, undefined)
  delete globalThis.document
  delete globalThis.Element
})

test("typing activity locks on the effective lock binding only", async () => {
  const bindings = await import("../../app/javascript/lib/shortcut_bindings.mjs")
  const source = await readFile(
    new URL("../../app/javascript/controllers/typing_activity_controller.js", import.meta.url),
    "utf8"
  )
  const Typing = new Function("Controller", "binding", "matches", source
    .replace(/^import .*\n/gm, "")
    .replace("export default class extends Controller", "return class extends Controller"))(class {}, bindings.binding, bindings.matches)
  const controller = new Typing()
  let locks = 0
  controller.manualLock = () => { locks += 1 }
  const press = (init) => controller.handleShortcut(key({ repeat: false, ...init }))

  globalThis.document = { body: { dataset: {} } }
  press({ key: "s", ctrlKey: true })
  assert.equal(locks, 0)
  press({ key: "l", ctrlKey: true })
  assert.equal(locks, 1)

  globalThis.document.body.dataset.shortcutOverrides = JSON.stringify({ lock: "Ctrl/Cmd+Shift+L" })
  press({ key: "l", ctrlKey: true })
  assert.equal(locks, 1)
  press({ key: "L", ctrlKey: true, shiftKey: true })
  assert.equal(locks, 2)
  delete globalThis.document
})

test("Ctrl/Cmd+S and Ctrl/Cmd+Enter focused inside the lock form do not submit it", async () => {
  const { controller, lock } = await controllerWithLockForm()
  lock.form.requestSubmit = () => { lock.control.clicks += 1 }
  const target = { closest: () => lock.form }

  controller.handleComboShortcut(key({ key: "s", metaKey: true, target }))
  controller.handleComboShortcut(key({ key: "Enter", metaKey: true, target }))
  assert.equal(lock.control.clicks, 0)
})

test("Ctrl/Cmd+S saves the page form in main", async () => {
  const page = clickSpy("button[type='submit'].btn-primary")
  const { controller } = await controllerWithLockForm({ pageForm: page.form })

  controller.handleComboShortcut(key({ key: "s", ctrlKey: true, target: { closest: () => null } }))
  assert.equal(page.control.clicks, 1)
})

test("Ctrl/Cmd+S with only a Delete button_to form in main clicks nothing", async () => {
  const del = clickSpy()
  const { controller } = await controllerWithLockForm({ pageForm: del.form })

  controller.handleComboShortcut(key({ key: "s", ctrlKey: true, target: { closest: () => null } }))
  assert.equal(del.control.clicks, 0)
})

test("Ctrl/Cmd+S focused inside a form clicks its submit", async () => {
  const page = clickSpy()
  const { controller } = await controllerWithLockForm()

  controller.handleComboShortcut(key({ key: "s", ctrlKey: true, target: { closest: () => page.form } }))
  assert.equal(page.control.clicks, 1)
})

test("unset shortcut uses the default; a user override replaces it", async () => {
  const { controller } = await controllerWithLockForm()
  let saves = 0
  controller.saveCurrentContext = () => { saves += 1 }
  const ctrlS = () => key({ key: "s", ctrlKey: true, target: {} })
  const ctrlY = () => key({ key: "y", ctrlKey: true, target: {} })

  globalThis.document = { body: { dataset: {} }, querySelector: () => null }
  controller.handleComboShortcut(ctrlS())
  assert.equal(saves, 1)

  globalThis.document.body.dataset.shortcutOverrides = JSON.stringify({ save: "Ctrl/Cmd+Y" })
  assert.equal(controller.handleComboShortcut(ctrlS()), false)
  assert.equal(controller.handleComboShortcut(ctrlY()), true)
  assert.equal(saves, 2)
  delete globalThis.document
})

test("matches handles chords, symbols and bare keys", async () => {
  const { matches } = await import("../../app/javascript/lib/shortcut_bindings.mjs")

  assert.ok(matches("Ctrl/Cmd+Shift+S", key({ key: "S", ctrlKey: true, shiftKey: true })))
  assert.ok(!matches("Ctrl/Cmd+S", key({ key: "s", ctrlKey: true, shiftKey: true })))
  assert.ok(matches("?", key({ key: "?", shiftKey: true })))
  assert.ok(matches("Alt+1", key({ key: "¡", code: "Digit1", altKey: true })))
  assert.ok(!matches("e", key({ key: "e", ctrlKey: true })))
  // Colemak: Ctrl+R sits on code KeyS and must not trigger Save; macOS Alt+p yields "π" but still matches.
  assert.ok(!matches("Ctrl/Cmd+S", key({ key: "r", code: "KeyS", ctrlKey: true })))
  assert.ok(matches("Alt+P", key({ key: "π", code: "KeyP", altKey: true })))
  assert.ok(matches("Ctrl/Cmd+ArrowUp", key({ key: "ArrowUp", ctrlKey: true })))
  assert.ok(matches("Alt+F2", key({ key: "F2", altKey: true })))
})

async function loadShortcutsController() {
  const bindings = await import("../../app/javascript/lib/shortcut_bindings.mjs")
  const source = await readFile(
    new URL("../../app/javascript/controllers/shortcuts_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/^import .*\n/gm, "")
    .replace("export default class extends Controller", "return class ShortcutsController extends Controller")

  return new Function("Controller", "DEFAULT_BINDINGS", "binding", "matches", "sequenceKeys", runnableSource)(
    class {}, bindings.DEFAULT_BINDINGS, bindings.binding, bindings.matches, bindings.sequenceKeys
  )
}
