import { Controller } from "@hotwired/stimulus"

// Generic toggle-able dropdown menu (e.g. a header "..." actions menu).
// Mirrors the toggle/outside-click/escape pattern used by add_to_list_controller
// and reminder_controller.
//
// The panel is shown through the Popover API (top layer) and placed against the trigger
// with viewport-aware flipping, so no `overflow: hidden` card or transformed ancestor can clip it.
export default class extends Controller {
  static targets = ["trigger", "dropdown"]

  connect() {
    this._outsideClick = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
    this._reposition = () => this.position()
    this._popover = typeof HTMLElement.prototype.showPopover === "function"
    if (this._popover) this.dropdownTarget.setAttribute("popover", "manual")
  }

  disconnect() {
    this._unlisten()
  }

  toggle(event) {
    event.stopPropagation()
    if (this.dropdownTarget.hidden) {
      this.dropdownTarget.hidden = false
      if (this._popover) this.dropdownTarget.showPopover()
      this.position()
      this.triggerTarget.setAttribute("aria-expanded", "true")
      document.addEventListener("click", this._outsideClick)
      window.addEventListener("resize", this._reposition)
      window.addEventListener("scroll", this._reposition, true)
    } else {
      this.close()
    }
  }

  close() {
    if (this._popover && this.dropdownTarget.matches(":popover-open")) this.dropdownTarget.hidePopover()
    this.dropdownTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this._unlisten()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  // Right-aligned under the trigger; flips above when there is no room below, clamps inside the viewport.
  position() {
    const menu = this.dropdownTarget
    const t = this.triggerTarget.getBoundingClientRect()
    const gap = 6
    const pad = 8
    menu.style.position = "fixed"
    const { width, height } = menu.getBoundingClientRect()
    let top = t.bottom + gap
    if (top + height > window.innerHeight - pad && t.top - gap - height >= pad) top = t.top - gap - height
    top = Math.max(pad, Math.min(top, window.innerHeight - height - pad))
    const left = Math.max(pad, Math.min(t.right - width, window.innerWidth - width - pad))
    menu.style.top = `${top}px`
    menu.style.left = `${left}px`
    menu.style.right = "auto"
  }

  _unlisten() {
    document.removeEventListener("click", this._outsideClick)
    window.removeEventListener("resize", this._reposition)
    window.removeEventListener("scroll", this._reposition, true)
  }
}
