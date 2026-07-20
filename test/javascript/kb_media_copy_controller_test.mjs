import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("media copy falls back to an absolute pasteable URL", async () => {
  let copied
  const navigator = { clipboard: { async writeText(value) { copied = value } } }
  const KbMediaCopyController = await loadController({ navigator })
  const controller = new KbMediaCopyController()
  controller.urlValue = "/knowledge-base/serve?src=0&file=clip.mp4"
  controller.mimeTypeValue = "video/mp4"
  controller.filenameValue = "clip.mp4"
  controller.hasLabelTarget = false
  controller.hasStatusTarget = false

  await controller.copy()

  assert.equal(copied, "http://idea.test/knowledge-base/serve?src=0&file=clip.mp4")
})

test("copy shortcut only handles command or control C", async () => {
  const KbMediaCopyController = await loadController({ navigator: { clipboard: {} } })
  const controller = new KbMediaCopyController()
  let copies = 0
  let prevented = 0
  controller.copy = () => { copies += 1 }

  controller.copyFromShortcut({ key: "c", ctrlKey: false, metaKey: false, preventDefault() { prevented += 1 } })
  controller.copyFromShortcut({ key: "C", ctrlKey: true, metaKey: false, preventDefault() { prevented += 1 } })

  assert.equal(copies, 1)
  assert.equal(prevented, 1)
})

async function loadController({ navigator }) {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_media_copy_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbMediaCopyController extends Controller")
  const window = {
    location: { href: "http://idea.test/knowledge-base" },
    clearTimeout() {},
    setTimeout() { return 1 }
  }

  return new Function(
    "Controller", "navigator", "ClipboardItem", "window", "fetch", "document", "createImageBitmap",
    runnableSource
  )(class {}, navigator, undefined, window, undefined, undefined, undefined)
}
