import { Controller } from "@hotwired/stimulus"

// Drag (or arrow-key) the sidebar's right edge to resize it. The width lives
// on the element as a custom property and in localStorage, so it survives
// reloads and tree re-renders without a round trip.
const STORE_KEY = "kb-sidebar-width"
const COLLAPSE_KEY = "kb-sidebar-collapsed"
const MIN = 180
const MAX = 560
const STEP = 16

export default class extends Controller {
  static targets = ["handle", "panel", "toggle", "collapse"]

  connect() {
    this.apply(this.stored() ?? this.panelTarget.offsetWidth)
    this.setCollapsed(this.read(COLLAPSE_KEY) === "1")

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

  // Wide screens: collapse the sidebar to a thin rail (remembered) so the document gets the width.
  toggleCollapse() {
    this.setCollapsed(!this.element.classList.contains("is-collapsed"))
    this.write(COLLAPSE_KEY, this.element.classList.contains("is-collapsed") ? "1" : "0")
  }

  setCollapsed(collapsed) {
    this.element.classList.toggle("is-collapsed", collapsed)
    if (!this.hasCollapseTarget) return
    this.collapseTarget.setAttribute("aria-expanded", String(!collapsed))
    this.collapseTarget.title = this.collapseTarget.ariaLabel = collapsed ? "Show files" : "Hide files"
  }

  read(key) {
    try { return localStorage.getItem(key) } catch { return null }
  }

  write(key, value) {
    try { localStorage.setItem(key, value) } catch { /* ponytail: storage disabled, collapse just won't persist */ }
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
