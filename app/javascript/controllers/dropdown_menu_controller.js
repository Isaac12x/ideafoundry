import { Controller } from "@hotwired/stimulus"

// Generic toggle-able dropdown menu (e.g. a header "..." actions menu).
// Mirrors the toggle/outside-click/escape pattern used by add_to_list_controller
// and reminder_controller.
export default class extends Controller {
  static targets = ["trigger", "dropdown"]

  connect() {
    this._outsideClick = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.dropdownTarget.hidden) {
      this.dropdownTarget.hidden = false
      this.triggerTarget.setAttribute("aria-expanded", "true")
      document.addEventListener("click", this._outsideClick)
    } else {
      this.close()
    }
  }

  close() {
    this.dropdownTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this._outsideClick)
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
