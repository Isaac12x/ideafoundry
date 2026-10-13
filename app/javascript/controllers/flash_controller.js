import { Controller } from "@hotwired/stimulus"

// Fades flash messages out. Successes auto-dismiss; errors stay until clicked.
export default class extends Controller {
  static values = { auto: { type: Boolean, default: true }, delay: { type: Number, default: 4000 } }

  connect() {
    if (this.autoValue) this._timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this._timer)
    clearTimeout(this._removeTimer)
  }

  dismiss() {
    this.element.style.transition = "opacity 0.35s ease"
    this.element.style.opacity = "0"
    this._removeTimer = setTimeout(() => this.element.remove(), 350)
  }
}
