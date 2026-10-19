import { Controller } from "@hotwired/stimulus"

// Collapsible region (project sections, material groups, test cards, protocol).
// The server renders the default state (open value + `hidden` on the body), so
// the first paint is right; a remembered choice is applied on connect, which
// is also what carries it across Turbo re-renders. Storage is best effort.
export default class extends Controller {
  static targets = ["toggle", "body"]
  static values = { key: String, open: Boolean }

  connect() {
    const stored = this.read()
    if (stored !== null) this.openValue = stored === "1"
    this.render()
  }

  toggle() {
    this.openValue = !this.openValue
    this.write(this.openValue ? "1" : "0")
  }

  // Programmatic open (jump links, kb-collapse:open); not remembered.
  show() {
    this.openValue = true
  }

  openValueChanged() {
    this.render()
  }

  render() {
    const open = this.openValue
    this.element.classList.toggle("is-open", open)
    if (this.hasBodyTarget) this.bodyTarget.hidden = !open
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  read() {
    if (!this.keyValue) return null
    try { return localStorage.getItem(this.keyValue) } catch { return null }
  }

  write(value) {
    if (!this.keyValue) return
    try { localStorage.setItem(this.keyValue, value) } catch { /* private mode */ }
  }
}
