import { Controller } from "@hotwired/stimulus"

// Settings index: restores scroll after coming back from a section (the window
// scrolls; there is no inner scroll container) and marks the last-opened row.
// Turbo advance visits reset scroll to top after render, so restore runs on
// connect AND once on the following turbo:load; restoration visits are re-applied
// harmlessly with the same value.
const SCROLL_KEY = "settings-index:scrollY"
const LAST_KEY = "settings-index:last"

const read = (store, key) => { try { return store.getItem(key) } catch { return null } }
const write = (store, key, value) => { try { store.setItem(key, value) } catch { /* private mode */ } }

export default class extends Controller {
  connect() {
    this._save = () => write(sessionStorage, SCROLL_KEY, String(Math.round(window.scrollY)))
    this._restore = () => {
      const y = parseInt(read(sessionStorage, SCROLL_KEY), 10)
      if (!Number.isNaN(y)) window.scrollTo(0, y)
    }
    this._onClick = (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
      const row = event.target.closest("a.settings-row")
      if (!row || !this.element.contains(row)) return
      this._save()
      write(localStorage, LAST_KEY, new URL(row.href, location.href).pathname)
    }
    this.element.addEventListener("click", this._onClick)
    document.addEventListener("turbo:before-visit", this._save)
    window.addEventListener("pagehide", this._save)
    // Restore once per arrival: now, and on the first turbo:load (Turbo resets scroll
    // after render). Not on later loads, so refreshes/morphs don't yank the user.
    this._restoreOnce = () => { this._restore(); this.stopRestoring() }
    document.addEventListener("turbo:load", this._restoreOnce)
    this._clearPills = () => this.element.querySelectorAll(".settings-last-viewed").forEach((el) => el.remove())
    document.addEventListener("turbo:before-cache", this._clearPills)
    this._restore()
    this.markLast()
  }

  disconnect() {
    this.element.removeEventListener("click", this._onClick)
    document.removeEventListener("turbo:before-visit", this._save)
    window.removeEventListener("pagehide", this._save)
    this.stopRestoring()
    document.removeEventListener("turbo:before-cache", this._clearPills)
  }

  stopRestoring() {
    document.removeEventListener("turbo:load", this._restoreOnce)
  }

  markLast() {
    this.element.querySelectorAll(".settings-last-viewed").forEach((el) => el.remove())
    const last = read(localStorage, LAST_KEY)
    if (!last) return
    const row = [...this.element.querySelectorAll("a.settings-row")]
      .find((a) => new URL(a.href, location.href).pathname === last)
    if (!row) return
    const pill = document.createElement("span")
    pill.className = "settings-last-viewed"
    pill.textContent = "Last viewed"
    // Sibling of the heading (not inside it) so the heading text stays clean.
    row.querySelector(".settings-row-info h3")?.after(pill)
  }
}
