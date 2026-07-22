import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("prompt uses the app dialog and resolves the entered value", async () => {
  const { controller, restore } = await buildController()

  try {
    const result = window.AppDialog.prompt("Name this tab", {
      title: "Add note tab",
      inputLabel: "Tab name",
      defaultValue: "Research",
      required: true,
    })

    assert.equal(controller.element.open, true)
    assert.equal(controller.titleTarget.textContent, "Add note tab")
    assert.equal(controller.inputLabelTarget.textContent, "Tab name")
    assert.equal(controller.inputTarget.value, "Research")
    assert.equal(controller.inputTarget.required, true)

    controller.inputTarget.value = "Decisions"
    controller.submit({ preventDefault() {} })

    assert.equal(await result, "Decisions")
    assert.equal(controller.element.open, false)
  } finally {
    restore()
  }
})

test("destructive confirmations are styled as danger and can be cancelled", async () => {
  const { controller, restore } = await buildController()

  try {
    const result = window.AppDialog.confirm("Delete this note?", { confirmLabel: "Delete" })

    assert.equal(controller.element.dataset.variant, "danger")
    assert.equal(controller.eyebrowTarget.textContent, "Careful")
    assert.equal(controller.confirmButtonTarget.textContent, "Delete")
    assert.equal(controller.confirmButtonTarget.classList.has("btn-danger"), true)

    controller.cancel({ preventDefault() {} })
    assert.equal(await result, false)
  } finally {
    restore()
  }
})

test("Turbo confirmations are routed through the app dialog", async () => {
  const { controller, restore } = await buildController()

  try {
    const result = window.Turbo.config.forms.confirm("Remove this item?", { method: "post" })
    assert.equal(controller.element.open, true)
    assert.equal(controller.element.dataset.variant, "danger")

    controller.submit({ preventDefault() {} })
    assert.equal(await result, true)
  } finally {
    restore()
  }
})

async function buildController() {
  const ControllerClass = await loadController()
  const previousWindow = globalThis.window
  const previousAnimationFrame = globalThis.requestAnimationFrame

  globalThis.window = { Turbo: { config: { forms: { confirm: () => false } } } }
  globalThis.requestAnimationFrame = (callback) => callback()

  const controller = new ControllerClass()
  controller.element = {
    dataset: {},
    open: false,
    showModal() { this.open = true },
    close() { this.open = false },
  }
  controller.formTarget = { reportValidity: () => true }
  controller.eyebrowTarget = textTarget()
  controller.titleTarget = textTarget()
  controller.messageTarget = textTarget()
  controller.fieldTarget = { hidden: false }
  controller.inputTarget = { type: "hidden", value: "", placeholder: "", required: false, focus() {}, select() {} }
  controller.inputLabelTarget = textTarget()
  controller.cancelButtonTarget = { hidden: false }
  controller.confirmButtonTarget = { textContent: "", classList: classList(), focus() {} }
  controller.connect()

  return {
    controller,
    restore() {
      controller.disconnect()
      globalThis.window = previousWindow
      globalThis.requestAnimationFrame = previousAnimationFrame
    },
  }
}

function textTarget() {
  return { textContent: "" }
}

function classList() {
  const values = new Set()
  return {
    toggle(name, force) {
      if (force) values.add(name)
      else values.delete(name)
    },
    has(name) { return values.has(name) },
  }
}

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/app_dialog_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class AppDialogController extends Controller")

  return new Function("Controller", runnableSource)(class {})
}
