import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "input"]

  connect() {
    this.sync()
  }

  sync() {
    const value = this.inputTarget.value
    this.outputTarget.textContent = value + "%"
    document.body.style.setProperty("--contrast", value + "%")
  }
}
