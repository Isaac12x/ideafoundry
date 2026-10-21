import { Controller } from "@hotwired/stimulus"

// Dismiss behaviour for <details> popovers: Escape or an outside click closes
// it; Escape returns focus to the summary.
export default class extends Controller {
  connect() {
    this._key = (event) => {
      if (event.key !== "Escape" || !this.element.open) return
      this.element.open = false
      this.element.querySelector("summary")?.focus()
    }
    this._away = (event) => {
      if (this.element.open && !this.element.contains(event.target)) this.element.open = false
    }
    this.element.addEventListener("keydown", this._key)
    document.addEventListener("pointerdown", this._away)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this._key)
    document.removeEventListener("pointerdown", this._away)
  }
}
