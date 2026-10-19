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

test("new folder with several picked files sends them to the server from their common parent", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const row = (rel) => ({ dataset: { kbTreeSrcParam: "1", kbTreeRelParam: rel } })
  controller._multiRows = () => [row("a/x.md"), row("a/y.md")]
  controller._node = { type: "file", rel: "a/x.md", src: 1, multi: true }
  let sent
  controller._submitForm = (url, method, fields) => { sent = fields }

  controller._create("folder")

  assert.deepEqual(sent, { src: 1, dir: "a", kind: "folder", "move[]": ["a/x.md", "a/y.md"] })
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

test("deleting a folder named like a number submits its path (Stimulus casts the param to Number)", async () => {
  const KbTreeController = await loadController()
  const controller = new KbTreeController()
  const submitted = []
  controller.menuTarget = { classList: { remove() {} } }
  controller.hasMenuTarget = true
  controller._unbindDocListeners = () => {}
  controller._submitForm = (...args) => submitted.push(args)
  controller.deleteUrlValue = "/knowledge-base/fs"
  controller._node = null
  controller.itemsTarget = {}
  controller.promptTarget = {}
  controller.itemTargets = []
  controller.menuTarget = {
    classList: { add() {}, remove() {} },
    style: {},
    getBoundingClientRect: () => ({ left: 0, top: 0 }),
    offsetWidth: 0,
    offsetHeight: 0
  }
  controller._onDocMousedown = controller._onDocKeydown = () => {}
  globalThis.document = { addEventListener() {}, removeEventListener() {} }
  globalThis.window = { innerWidth: 100, innerHeight: 100, AppDialog: { confirm: async () => true } }

  controller._open({ type: "dir", rel: 2024, src: 1 }, 0, 0, null)
  await controller.destroy({ stopPropagation() {} })

  assert.deepEqual(submitted, [["/knowledge-base/fs", "delete", { src: 1, path: "2024" }]])
})

test("delete falls back to window.confirm when the app dialog is missing", async () => {
  const KbTreeController = await loadController()
  const controller = new KbTreeController()
  const submitted = []
  controller._hide = () => {}
  controller._submitForm = (...args) => submitted.push(args)
  controller.deleteUrlValue = "/knowledge-base/fs"
  controller._node = { type: "file", rel: "notes/a.md", src: 0 }
  const asked = []
  globalThis.window = { confirm: (message) => { asked.push(message); return true } }

  await controller.destroy({ stopPropagation() {} })

  assert.deepEqual(asked, ['Delete "a.md"?'])
  assert.deepEqual(submitted, [["/knowledge-base/fs", "delete", { src: 0, path: "notes/a.md" }]])

  globalThis.window = { confirm: () => false }
  await controller.destroy({ stopPropagation() {} })
  assert.equal(submitted.length, 1)
})

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_tree_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/^import .*$/gm, "")
    .replace("export default class extends Controller", "return class KbTreeController extends Controller")
  const { confirmDialog, alertDialog } = await import("../../app/javascript/lib/app_dialog.mjs")

  return new Function("Controller", "confirmDialog", "alertDialog", runnableSource)(class {}, confirmDialog, alertDialog)
}

test("a file loaded into kb-content from any link moves the active highlight", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const mk = (on, src, rel) => {
    const set = new Set(on ? ["is-active"] : [])
    const link = { set, classList: { add: (c) => set.add(c) } }
    return {
      dataset: { kbTreeSrcParam: src, kbTreeRelParam: rel }, set,
      classList: { add: (c) => set.add(c), remove: (c) => set.delete(c), contains: (c) => set.has(c) },
      querySelector: () => link, link
    }
  }
  const oldRow = mk(true, 0, "a.md")
  const newRow = mk(false, 1, "b/c.md")
  controller._queueSync = () => {}
  controller.element = {
    querySelectorAll: (sel) => sel === ".kb-file-row" ? [oldRow, newRow] : [oldRow, newRow],
  }
  const load = (src) => controller._highlightFrameFile({ target: { id: "kb-content", src } })

  load("http://x/knowledge-base/file?src=1&file=b%2Fc.md")
  assert.equal(oldRow.set.has("is-active"), false)
  assert.equal(newRow.set.has("is-active"), true)
  assert.equal(newRow.link.set.has("is-active"), true)

  load("http://x/knowledge-base/projects/3") // not a file URL: unchanged
  assert.equal(newRow.set.has("is-active"), true)
})

test("dropping a project child on a role shelf sends only its role, scoped to that project", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  controller.projectMaterialsUrlValue = "/materials"
  controller.element = { classList: { remove() {}, add() {} } }
  let sent
  controller._submitForm = (url, method, fields) => { sent = { url, method, fields } }
  const shelf = (role, projectRel = "Lab", src = 0) => ({
    params: { role, projectRel, src },
    currentTarget: { classList: { remove() {}, add() {} } },
    dataTransfer: {},
    preventDefault() { sent = sent || "prevented" }
  })

  controller._drag = { type: "file", rel: "Lab/a.txt", src: 0 }
  controller.roleDrop(shelf("output"))
  assert.deepEqual(sent, { url: "/materials", method: "patch", fields: { src: 0, path: "Lab", name: "a.txt", role: "output", tree_only: "1" } })

  sent = undefined
  controller._drag = { type: "dir", rel: "Lab/raw", src: 0 }
  controller.roleDrop(shelf("")) // Inbox = blank role
  assert.equal(sent.fields.role, "")

  for (const drag of [
    { type: "file", rel: "Other/a.txt", src: 0 },     // another project's file
    { type: "file", rel: "Lab/Tests/x.md", src: 0 },  // nested, not a direct child
    { type: "dir", rel: "Lab/Tests", src: 0 },        // the Tests dir is not a material
    { type: "file", rel: "Lab/a.txt", src: 1 }        // another source
  ]) {
    sent = undefined
    controller._drag = drag
    controller.roleDrop(shelf("working"))
    assert.equal(sent, undefined, `${drag.rel} must not be re-roled`)
  }
})
