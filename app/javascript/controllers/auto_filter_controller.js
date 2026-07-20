import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = 'ideas-filters-open'

export default class extends Controller {
  static targets = ["form", "search", "body", "toggleBtn", "activeDot"]

  connect() {
    // Closed by default; only reopen if the user left it open last session.
    const open = localStorage.getItem(STORAGE_KEY) === 'true'
    this._setOpen(open, false)
  }

  toggleCollapse() {
    const open = this.bodyTarget.classList.contains('filter-body--collapsed')
    this._setOpen(open, true)
  }

  _setOpen(open, save) {
    this.bodyTarget.classList.toggle('filter-body--collapsed', !open)
    if (this.hasToggleBtnTarget) {
      this.toggleBtnTarget.classList.toggle('filter-toggle-btn--open', open)
    }
    if (save) localStorage.setItem(STORAGE_KEY, String(open))
  }

  submit() {
    this.formTarget.requestSubmit()
  }

  debouncedSubmit() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this.submit(), 400)
  }
}
