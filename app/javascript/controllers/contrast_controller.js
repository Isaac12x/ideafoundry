import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "input"]

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasInputTarget) return
    const value = this.inputTarget.value
    if (this.hasOutputTarget) this.outputTarget.textContent = value + "%"
    document.body.style.setProperty("--contrast", value + "%")
  }
}
