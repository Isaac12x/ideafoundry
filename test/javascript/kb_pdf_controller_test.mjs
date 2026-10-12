import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

// The text layer is positioned in absolute pixels, so a width change has to
// rescale every rendered page or selection drifts off the glyphs.
test("resizing rescales each text layer to the new page width", async () => {
  const KbPdfController = await loadController()
  const controller = new KbPdfController()
  controller.element = { clientWidth: 600 }
  controller._width = 900

  const styles = {}
  const rescaled = []
  controller._layers = [{
    holder: { clientWidth: 600 },
    page: { getViewport: ({ scale }) => ({ scale, width: 300 * scale }) },
    div: { style: { setProperty(name, value) { styles[name] = value } } },
    textLayer: { update({ viewport }) { rescaled.push(viewport.scale) } }
  }]

  controller._onResize()

  assert.equal(styles["--scale-factor"], 2)
  assert.deepEqual(rescaled, [2])
  assert.equal(controller._width, 600)
})

test("resizing does nothing when the width is unchanged or zero", async () => {
  const KbPdfController = await loadController()
  const controller = new KbPdfController()
  controller._layers = [{
    holder: { clientWidth: 900 },
    page: { getViewport: () => { throw new Error("should not re-measure") } },
    div: { style: { setProperty() { throw new Error("should not restyle") } } },
    textLayer: { update() { throw new Error("should not update") } }
  }]

  controller._width = 900
  controller.element = { clientWidth: 900 }
  controller._onResize()

  controller.element = { clientWidth: 0 }
  controller._onResize()

  assert.equal(controller._width, 900)
})

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_pdf_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbPdfController extends Controller")

  return new Function("Controller", "window", "document", "localStorage", runnableSource)(
    class {}, undefined, undefined, undefined
  )
}
