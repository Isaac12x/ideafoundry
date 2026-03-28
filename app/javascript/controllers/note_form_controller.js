import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  reset() {
    this.element.reset()
    if (this.hasInputTarget) {
      this.inputTarget.style.height = "auto"
      this.inputTarget.focus()
    }
  }

  autoResize() {
    if (!this.hasInputTarget) return
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = el.scrollHeight + "px"
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }
}
