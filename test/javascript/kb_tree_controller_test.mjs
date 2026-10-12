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

test("favouriting repaints the row locally and never blocks on the server", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  let sent
  controller._postJson = async (url, method, fields) => { sent = { url, method, fields }; return {} }
  controller.preferenceUrlValue = "/kb/fs/preference"

  const row = { dataset: {} }
  const button = {
    dataset: {},
    classList: { toggle(_name, on) { this.on = on } },
    closest: () => row,
    setAttribute(name, value) { this[name] = value }
  }

  await controller.toggleFavorite({
    preventDefault() {}, stopPropagation() {},
    currentTarget: button,
    params: { type: "file", rel: "a.md", src: 1, favorite: false }
  })

  assert.equal(button.classList.on, true)
  assert.equal(button.dataset.kbTreeFavoriteParam, true)
  assert.equal(button["aria-pressed"], "true")
  assert.equal(row.dataset.kbTreeFavoriteParam, true)
  assert.equal(sent.method, "patch")
  assert.equal(sent.fields.favorite, "1")
})

test("a rejected favourite rolls the star back", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  controller._postJson = async () => ({ error: "Nope." })
  controller._alert = () => {}

  const button = {
    dataset: {},
    classList: { toggle(_name, on) { this.states = [...(this.states ?? []), on] } },
    closest: () => null,
    setAttribute() {}
  }

  await controller.toggleFavorite({
    preventDefault() {}, stopPropagation() {},
    currentTarget: button,
    params: { type: "file", rel: "a.md", src: 1, favorite: false }
  })

  assert.deepEqual(button.classList.states, [true, false])
})

test("naming commits only real changes, and restores the old name otherwise", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const calls = []
  controller._postJson = async (...args) => { calls.push(args); return { rel: "b.md", name: "b.md" } }
  controller._applyRename = () => {}
  controller.renameUrlValue = "/kb/fs/rename"

  const { row, input } = namingRow("a.md")

  input.value = "  a.md  "
  await controller.nameCommit({ target: input })
  assert.equal(calls.length, 0, "an unchanged name is not sent")
  assert.equal(input.value, "a.md")

  row.classList.add("is-naming")
  input.value = "b.md"
  await controller.nameCommit({ target: input })
  assert.equal(calls.length, 1)
  assert.deepEqual(calls[0][2], { src: "1", path: "a.md", name: "b.md" })
})

test("escape abandons an inline rename", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const { row, input } = namingRow("a.md")
  input.value = "typed-something-else"

  controller.nameKeydown({ key: "Escape", target: input, preventDefault() {}, stopPropagation() {} })

  assert.equal(input.value, "a.md")
  assert.equal(row.classList.contains("is-naming"), false)
})

// A minimal stand-in for one tree row mid-rename.
function namingRow(name) {
  const input = {
    value: name,
    hidden: false,
    dataset: { original: name },
    closest: () => row
  }
  const classes = new Set(["is-naming"])
  const row = {
    draggable: false,
    dataset: { kbTreeSrcParam: "1", kbTreeRelParam: "a.md" },
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name)
    },
    querySelector: () => input,
    querySelectorAll: () => []
  }
  return { row, input }
}

test("tree arrow keys move between visible items and collapse/expand folders", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const mk = (dir, collapsed) => ({ dir, collapsed, matches: () => true })
  const folder = mk(true, false)
  const file = mk(false, null)
  const items = [folder, file]
  let focused, toggled = 0
  controller._items = () => items
  controller._isDir = (r) => r.dir
  controller._collapsed = (r) => r.collapsed
  controller._toggle = () => { toggled += 1 }
  controller._parentItem = (r) => (r === file ? folder : null)
  controller._focusItem = (r) => { focused = r }
  const press = (target, key) => {
    let prevented = false
    controller._treeKeydown({ target, key, preventDefault() { prevented = true } })
    return prevented
  }

  assert.equal(press(folder, "ArrowDown"), true)
  assert.equal(focused, file)
  press(file, "ArrowUp")
  assert.equal(focused, folder)
  press(folder, "ArrowRight")
  assert.equal(focused, file, "right on an open folder enters it")
  press(file, "ArrowLeft")
  assert.equal(focused, folder, "left on a file goes to its folder")
  press(folder, "ArrowLeft")
  assert.equal(toggled, 1, "left on an open folder collapses it")
  press(folder, "End")
  assert.equal(focused, file)
  press(folder, "Home")
  assert.equal(focused, folder)
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
