import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = 'ideas-filters-open'

export default class extends Controller {
  static targets = ["form", "search", "body", "toggleBtn", "activeDot"]
  static values = { filtersActive: Boolean }

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const open = this.filtersActiveValue || stored !== 'false'
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
