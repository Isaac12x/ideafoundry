import { Controller } from "@hotwired/stimulus"
import { hazeVars } from "lib/privacy_guard"

// Settings preview: a mock page + nav strip hazed with the strength currently selected. Hold the button to see it;
// dragging the strength slider shows it briefly too. Purely visual, nothing is saved here.
export default class extends Controller {
  static targets = ["strength", "tile", "page", "state", "enabled", "offField", "clear", "lockHint"]

  connect() {
    this.update()
    this.onStatus = (e) => this.gate(e.detail.verified)
    window.addEventListener("privacy-gaze:status", this.onStatus)
    this.gate(document.body.dataset.privacyGazeVerified === "true")
  }
  disconnect() { clearTimeout(this.timer); window.removeEventListener("privacy-gaze:status", this.onStatus) }

  // The haze can only be turned off while the owner is verified looking (un-gazed). While it is on and not verified the
  // switch is locked (fails closed until the first camera reading); the "0" field goes too, or a slider save would post it.
  // The server checks again from the `clear` flag below.
  gate(verified) {
    if (!this.hasEnabledTarget) return
    const locked = this.enabledTarget.checked && !verified
    this.enabledTarget.disabled = locked
    this.offFieldTarget.disabled = locked
    this.clearTarget.value = verified ? "1" : "0"
    this.lockHintTarget.hidden = !locked
    this.enabledTarget.setAttribute("aria-describedby", locked ? "privacy_gaze_lock_hint" : "")
  }

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
