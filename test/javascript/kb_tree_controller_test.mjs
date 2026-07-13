import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("external files are recognised as copy drops without an internal drag", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  controller._drag = null

  assert.equal(controller._hasExternalFiles({ dataTransfer: { types: ["Files"] } }), true)
  controller._drag = { type: "file" }
  assert.equal(controller._hasExternalFiles({ dataTransfer: { types: ["Files"] } }), false)
})

test("drop routes external files to upload and internal nodes to move", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  let uploaded
  controller._uploadFiles = (files, destination) => { uploaded = { files, destination } }
  const files = [{ name: "note.md" }]
  let prevented = 0

  controller.drop({
    params: { type: "dir", rel: "research", src: 0 },
    dataTransfer: { types: ["Files"], files },
    currentTarget: { classList: { remove() {} } },
    preventDefault() { prevented += 1 }
  })

  assert.equal(prevented, 1)
  assert.deepEqual(uploaded.files, files)
  assert.equal(uploaded.destination.rel, "research")
})

test("AI jobs target folders directly and files through their parent", async () => {
  const Controller = await loadController()
  const controller = new Controller()

  assert.equal(controller._targetDir({ type: "dir", rel: "research" }), "research")
  assert.equal(controller._targetDir({ type: "file", rel: "research/note.md" }), "research")
  assert.equal(controller._targetDir({ type: "root", rel: "" }), "")
})

test("AI job requests bubble from the selected context-menu action", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  controller._node = { type: "file", rel: "research/note.md", src: 2 }
  controller._hide = () => {}
  let dispatched
  const PreviousCustomEvent = globalThis.CustomEvent
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = type
      Object.assign(this, options)
    }
  }

  try {
    controller.job({
      stopPropagation() {},
      currentTarget: { dispatchEvent(event) { dispatched = event } }
    })
  } finally {
    globalThis.CustomEvent = PreviousCustomEvent
  }

  assert.equal(dispatched.type, "kb-job:open")
  assert.equal(dispatched.bubbles, true)
  assert.deepEqual(dispatched.detail, {
    src: 2,
    path: "research/note.md",
    contextKind: "file",
    label: "note.md"
  })
})

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_tree_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbTreeController extends Controller")

  return new Function("Controller", runnableSource)(class {})
}
