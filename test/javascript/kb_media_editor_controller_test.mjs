import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

test("timeline validation prevents an out point before the in point", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  let validity = ""
  controller.hasTrimStartTarget = true
  controller.hasTrimEndTarget = true
  controller.trimStartTarget = { value: "8" }
  controller.trimEndTarget = { value: "4", setCustomValidity(value) { validity = value } }

  assert.equal(controller.validateTrim(), false)
  assert.equal(validity, "Out must be after in")

  controller.trimEndTarget.value = "9"
  assert.equal(controller.validateTrim(), true)
  assert.equal(validity, "")
})

test("preview applies the same timing, sound, grade, and transform recipe shown in controls", async () => {
  const Controller = await loadController()
  const controller = new Controller()
  const media = { style: {}, volume: 1, muted: false }
  const output = () => ({ textContent: "" })
  Object.assign(controller, {
    hasCanvasTarget: false,
    hasMediaTarget: true, mediaTarget: media,
    hasBrightnessTarget: true, brightnessTarget: { value: "0.2" },
    hasContrastTarget: true, contrastTarget: { value: "1.1" },
    hasSaturationTarget: true, saturationTarget: { value: "0.8" },
    hasGrayscaleTarget: true, grayscaleTarget: { checked: true },
    hasSpeedTarget: true, speedTarget: { value: "1.25" },
    hasVolumeTarget: true, volumeTarget: { value: "1.4" },
    hasMuteTarget: true, muteTarget: { checked: true },
    hasRotateTarget: true, rotateTarget: { value: "90" },
    hasFlipHorizontalTarget: true, flipHorizontalTarget: { checked: true },
    hasFlipVerticalTarget: true, flipVerticalTarget: { checked: false },
    hasCropAspectTarget: true, cropAspectTarget: { value: "16:9" },
    hasBrightnessOutputTarget: true, brightnessOutputTarget: output(),
    hasContrastOutputTarget: true, contrastOutputTarget: output(),
    hasSaturationOutputTarget: true, saturationOutputTarget: output(),
    hasSpeedOutputTarget: true, speedOutputTarget: output(),
    hasVolumeOutputTarget: true, volumeOutputTarget: output()
  })

  controller.preview()

  assert.equal(media.playbackRate, 1.25)
  assert.equal(media.volume, 1, "native preview volume is capped while the render can amplify to 200%")
  assert.equal(media.muted, true)
  assert.match(media.style.filter, /brightness\(1\.2\).*grayscale\(1\)/)
  assert.equal(media.style.transform, "rotate(90deg) scale(-1, 1)")
  assert.equal(media.style.aspectRatio, "16 / 9")
  assert.equal(controller.speedOutputTarget.textContent, "1.25×")
  assert.equal(controller.volumeOutputTarget.textContent, "140%")
})

test("editor clock retains millisecond precision for trim work", async () => {
  const Controller = await loadController()
  const controller = new Controller()

  assert.equal(controller.formatTime(125.678), "02:05.678")
})

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/kb_media_editor_controller.js", import.meta.url),
    "utf8"
  )
  const runnableSource = source
    .replace(/import \{ Controller \} from "@hotwired\/stimulus"\n\n/, "")
    .replace("export default class extends Controller", "return class KbMediaEditorController extends Controller")

  return new Function("Controller", runnableSource)(class {})
}
