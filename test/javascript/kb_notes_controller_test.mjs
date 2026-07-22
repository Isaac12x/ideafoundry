import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("adding a note tab uses the app prompt", async () => {
  const Controller = await loadController()
  const controller = preparedController(Controller)
  const previousWindow = globalThis.window
  let promptOptions

  globalThis.window = {
    AppDialog: {
      prompt: async (_message, options) => {
        promptOptions = options
        return "  Research  "
      },
    },
  }

  try {
    await controller.addTab({ stopPropagation() {} })
  } finally {
    globalThis.window = previousWindow
  }

  assert.equal(promptOptions.title, "Add note tab")
  assert.equal(promptOptions.inputLabel, "Tab name")
  assert.equal(promptOptions.required, true)
  assert.equal(controller._customTabs.length, 1)
  assert.equal(controller._customTabs[0].label, "Research")
  assert.equal(controller._activeKey, controller._customTabs[0].id)
})

test("deleting a note tab waits for confirmation", async () => {
  const Controller = await loadController()
  const controller = preparedController(Controller)
  controller._customTabs = [{ id: "custom_1", label: "Research" }]
  controller._activeKey = "custom_1"
  const previousWindow = globalThis.window
  const previousStorage = Object.getOwnPropertyDescriptor(globalThis, "localStorage")
  let confirmed = false
  const removed = []

  globalThis.window = { AppDialog: { confirm: async () => confirmed } }
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: { removeItem: (key) => removed.push(key) },
  })

  try {
    await controller.closeTab({ stopPropagation() {}, currentTarget: { dataset: { closeKey: "custom_1" } } })
    assert.equal(controller._customTabs.length, 1)

    confirmed = true
    await controller.closeTab({ stopPropagation() {}, currentTarget: { dataset: { closeKey: "custom_1" } } })
  } finally {
    globalThis.window = previousWindow
    if (previousStorage) Object.defineProperty(globalThis, "localStorage", previousStorage)
    else delete globalThis.localStorage
  }

  assert.equal(controller._customTabs.length, 0)
  assert.deepEqual(removed, ["kb_note_custom_1"])
  assert.equal(controller._activeKey, "general")
})

function preparedController(Controller) {
  const controller = new Controller()
  controller._customTabs = []
  controller._activeKey = "general"
  controller._saveContent = () => {}
  controller._saveCustomTabs = () => {}
  controller._expand = () => { controller._expanded = true }
  controller._renderTabs = () => {}
  controller._loadContent = () => {}
  return controller
}

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_notes_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/^import .*$/gm, "")
    .replace("export default class extends Controller", "return class KbNotesController extends Controller")

  return new Function("Controller", runnableSource)(class {})
}
