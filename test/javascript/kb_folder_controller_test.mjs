import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("collapse and uncollapse all update every nested folder and persist the state", async () => {
  const storage = memoryStorage()
  const KbFolderController = await loadController(storage)
  const first = folderGroup("0:research")
  const second = folderGroup("0:research/sources")
  const controller = new KbFolderController()
  controller.element = rootGroup([first, second])

  controller.collapseAll({ stopPropagation() {} })

  assert.equal(first.classList.contains("is-collapsed"), true)
  assert.equal(second.classList.contains("is-collapsed"), true)
  assert.deepEqual(JSON.parse(storage.getItem("kb-tree-collapsed")), ["0:research", "0:research/sources"])

  controller.expandAll({ stopPropagation() {} })

  assert.equal(first.classList.contains("is-collapsed"), false)
  assert.equal(second.classList.contains("is-collapsed"), false)
  assert.deepEqual(JSON.parse(storage.getItem("kb-tree-collapsed")), [])
})

async function loadController(localStorage) {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_folder_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus";?\n\n/, "")
    .replace("export default class extends Controller", "return class KbFolderController extends Controller")

  return new Function("Controller", "localStorage", runnableSource)(class {}, localStorage)
}

function memoryStorage() {
  const values = new Map()
  return {
    getItem(key) { return values.get(key) ?? null },
    setItem(key, value) { values.set(key, value) }
  }
}

function folderGroup(key) {
  const [src, ...rel] = key.split(":")
  const header = { dataset: { kbTreeSrcParam: src, kbTreeRelParam: rel.join(":") } }
  const classes = new Set()
  return {
    classList: {
      contains(name) { return classes.has(name) },
      add(name) { classes.add(name) },
      toggle(name, force) {
        if (force === true) classes.add(name)
        else if (force === false) classes.delete(name)
        else if (classes.has(name)) classes.delete(name)
        else classes.add(name)
        return classes.has(name)
      }
    },
    querySelector(selector) { return selector === ":scope > .kb-dir-header" ? header : null }
  }
}

function rootGroup(groups) {
  return {
    querySelector() { return null },
    querySelectorAll(selector) { return selector === ".kb-dir-group" ? groups : [] }
  }
}
