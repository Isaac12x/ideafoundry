import { Controller } from "@hotwired/stimulus"
import { hazeVars } from "lib/privacy_guard"

// Settings preview: a mock page + nav strip hazed with the strength currently selected. Hold the button to see it;
// dragging the strength slider shows it briefly too. Purely visual, nothing is saved here.
export default class extends Controller {
  static targets = ["strength", "tile", "page", "state"]

  connect() { this.update() }
  disconnect() { clearTimeout(this.timer) }

  update() {
    for (const [k, v] of Object.entries(hazeVars(this.strengthTarget.value))) this.tileTarget.style.setProperty(k, v)
  }

  // slider moved: show the result for a moment
  peek() {
    this.update()
    this.show(true)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.show(false), 1200)
  }

  hold(event) {
    if (event.type === "keydown" && (event.repeat || !/^( |Enter)$/.test(event.key))) return
    event.preventDefault()
    clearTimeout(this.timer)
    this.update()
    this.show(true)
  }

  release(event) {
    if (event.type === "keyup" && !/^( |Enter)$/.test(event.key)) return
    this.show(false)
  }

  show(hazed) {
    this.pageTarget.classList.toggle("is-hazed", hazed)
    this.stateTarget.textContent = hazed ? "Hazed" : "Clear"
    this.stateTarget.dataset.hazed = hazed
  }
}
