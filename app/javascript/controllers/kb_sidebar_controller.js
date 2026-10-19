import { Controller } from "@hotwired/stimulus"

// Drag (or arrow-key) the sidebar's right edge to resize it. The width lives
// on the element as a custom property and in localStorage, so it survives
// reloads and tree re-renders without a round trip.
const STORE_KEY = "kb-sidebar-width"
const MIN = 180
const MAX = 560
const STEP = 16

export default class extends Controller {
  static targets = ["handle", "panel", "toggle"]

  connect() {
    this.apply(this.stored() ?? this.panelTarget.offsetWidth)

    this._onMove = (event) => this.move(event)
    this._onUp = () => this.stop()
  }

  disconnect() {
    this.stop()
  }

  start(event) {
    event.preventDefault()
    this.panelTarget.classList.add("is-resizing")
    document.body.classList.add("kb-resizing")
    window.addEventListener("pointermove", this._onMove)
    window.addEventListener("pointerup", this._onUp)
    window.addEventListener("pointercancel", this._onUp)
  }

  move(event) {
    this.apply(event.clientX - this.panelTarget.getBoundingClientRect().left)
  }

  stop() {
    this.panelTarget.classList.remove("is-resizing")
    document.body.classList.remove("kb-resizing")
    window.removeEventListener("pointermove", this._onMove)
    window.removeEventListener("pointerup", this._onUp)
    window.removeEventListener("pointercancel", this._onUp)
  }

  nudge(event) {
    const delta = { ArrowLeft: -STEP, ArrowRight: STEP }[event.key]
    if (delta === undefined) return

    event.preventDefault()
    this.apply(this.panelTarget.offsetWidth + delta)
  }

  // Narrow screens: the sidebar is an off-canvas drawer (CSS); this flips it.
  toggleDrawer() {
    this.setDrawer(!this.element.classList.contains("is-drawer-open"))
  }

  closeDrawer() {
    this.setDrawer(false)
  }

  // Picking something in the tree closes the drawer so the content shows.
  maybeClose(event) {
    if (event.target.closest("a, .kb-file-row")) this.setDrawer(false)
  }

  setDrawer(open) {
    this.element.classList.toggle("is-drawer-open", open)
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  apply(width) {
    const clamped = Math.round(Math.min(MAX, Math.max(MIN, width)))
    this.panelTarget.style.setProperty("--kb-sidebar-width", `${clamped}px`)
    if (this.hasHandleTarget) this.handleTarget.setAttribute("aria-valuenow", clamped)

    try {
      localStorage.setItem(STORE_KEY, clamped)
    } catch {
      // ponytail: storage disabled — the width just won't survive a reload.
    }
  }

  stored() {
    try {
      const value = Number(localStorage.getItem(STORE_KEY))
      return Number.isFinite(value) && value > 0 ? value : null
    } catch {
      return null
    }
  }
}
