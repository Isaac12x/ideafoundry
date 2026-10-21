import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { formatDims, SUPPORTED } from "../../app/javascript/kb_viewers/model.js"

test("dimensions read as X × Y × Z with four significant digits", () => {
  assert.equal(formatDims({ x: 10, y: 20.123456, z: 0.00012345 }), "10 × 20.12 × 0.0001234")
  assert.equal(formatDims({ x: 1234.5678, y: 0, z: 5 }), "1235 × 0 × 5")
})

test("every mesh and B-rep extension the server routes here has a loader", () => {
  for (const ext of [".stl", ".obj", ".ply", ".gltf", ".glb", ".3mf", ".fbx", ".dae", ".step", ".stp", ".iges", ".igs", ".brep"]) {
    assert.ok(SUPPORTED.includes(ext), ext)
  }
})

test("comic pager clamps at both ends and remembers the page", async () => {
  const source = (await readFile(new URL("../../app/javascript/controllers/kb_comic_controller.js", import.meta.url), "utf8"))
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbComicController extends Controller")
  const stored = {}
  const Comic = new Function("Controller", "localStorage", "Image", "window", source)(
    class { dispatch() {} }, { getItem: (k) => stored[k] ?? null, setItem: (k, v) => { stored[k] = v } }, class {}, { addEventListener() {}, removeEventListener() {} }
  )
  const comic = new Comic()
  const el = () => ({ disabled: false, textContent: "", alt: "", src: "", scrollTop: 1 })
  Object.assign(comic, { pagesValue: ["a", "b", "c"], keyValue: "0:x.cbz", pageTarget: el(), countTarget: el(), previousTarget: el(), nextTarget: el(), stageTarget: el() })
  comic._storeKey = "kb-resume:comic:0:x.cbz"

  comic.show(-5)
  assert.deepEqual([comic.index, comic.previousTarget.disabled, comic.countTarget.textContent], [0, true, "1 / 3"])
  comic.next(); comic.next(); comic.next()
  assert.deepEqual([comic.index, comic.nextTarget.disabled, comic.pageTarget.src], [2, true, "c"])
  assert.equal(stored["kb-resume:comic:0:x.cbz"], "2")
})
