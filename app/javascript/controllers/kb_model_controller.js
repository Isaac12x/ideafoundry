import { Controller } from "@hotwired/stimulus"

// 3D model viewer shell. three.js (and occt-import-js for STEP/IGES/BREP) live in a separate esbuild bundle
// that is imported only when a model is opened; this controller owns the buttons and the bundle's lifetime.
export default class extends Controller {
  static targets = ["stage", "control", "wireframe", "dims", "status"]
  static values = { url: String, ext: String, bundleUrl: String, wasmUrl: String }

  async connect() {
    this.gone = false
    try {
      const { mountModel } = await import(this.bundleUrlValue)
      const viewer = await mountModel({ host: this.stageTarget, url: this.urlValue, ext: this.extValue, wasmUrl: this.wasmUrlValue })
      if (this.gone) return viewer.dispose()
      this.viewer = viewer
      this.controlTargets.forEach((button) => { button.disabled = false })
      this.dimsTarget.textContent = viewer.dimsText
      this.statusTarget.textContent = ""
    } catch (error) {
      if (this.gone) return
      this.statusTarget.textContent = error?.message || "Could not open this 3D model."
      this.statusTarget.classList.add("kb-viewer-notice--error")
    }
  }

  disconnect() {
    this.gone = true
    this.viewer?.dispose()
    this.viewer = null
  }

  reset() { this.viewer?.reset() }

  toggleWireframe() {
    const on = this.wireframeTarget.getAttribute("aria-pressed") !== "true"
    this.wireframeTarget.setAttribute("aria-pressed", String(on))
    this.viewer?.setWireframe(on)
  }
}
