import { Controller } from "@hotwired/stimulus"

// Page-flipper for comic archives (.cbz/.cbr/.cb7/.cbt). Pages are plain image URLs served one entry at a
// time by KbArchivesController; the next page is preloaded and the last page is remembered per file.
// Bookmarks panel hooks: emits "kb-comic:page" ({ page, pages }, 1-based); accepts "kb-comic:goto" (detail = page).
export default class extends Controller {
  static targets = ["page", "count", "previous", "next", "stage"]
  static values = { pages: Array, key: String }

  connect() {
    this._storeKey = `kb-resume:comic:${this.keyValue}`
    const saved = parseInt(localStorage.getItem(this._storeKey) || "0", 10)
    this.index = Number.isInteger(saved) && saved >= 0 && saved < this.pagesValue.length ? saved : 0
    this._onKey = (event) => {
      if (!(this.element.contains(event.target) || event.target === document.body)) return
      if (event.metaKey || event.ctrlKey || event.altKey || event.target.closest?.("input, textarea, select, [contenteditable]")) return
      const moves = { ArrowRight: () => this.next(), ArrowLeft: () => this.previous(), Home: () => this.show(0), End: () => this.show(this.pagesValue.length - 1) }
      if (moves[event.key]) { event.preventDefault(); moves[event.key]() }
    }
    window.addEventListener("keydown", this._onKey)
    this._onGoto = (event) => this.show((parseInt(event.detail, 10) || 1) - 1)
    this.element.addEventListener("kb-comic:goto", this._onGoto)
    this.show(this.index)
  }

  disconnect() {
    window.removeEventListener("keydown", this._onKey)
    this.element.removeEventListener("kb-comic:goto", this._onGoto)
  }

  previous() { this.show(this.index - 1) }

  next() { this.show(this.index + 1) }

  show(index) {
    const last = this.pagesValue.length - 1
    this.index = Math.min(Math.max(index, 0), last)
    this.pageTarget.src = this.pagesValue[this.index]
    this.pageTarget.alt = `Page ${this.index + 1} of ${last + 1}`
    this.countTarget.textContent = `${this.index + 1} / ${last + 1}`
    this.previousTarget.disabled = this.index === 0
    this.nextTarget.disabled = this.index === last
    this.stageTarget.scrollTop = 0
    localStorage.setItem(this._storeKey, String(this.index))
    this.dispatch("page", { detail: { page: this.index + 1, pages: last + 1 } })
    if (this.index < last) new Image().src = this.pagesValue[this.index + 1]
  }
}
