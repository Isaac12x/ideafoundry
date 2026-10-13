import { Controller } from "@hotwired/stimulus"

// Reference picker dialog: opens itself as a modal, filters the list,
// bulk-selects what's visible, keeps "Pull selected" and the count in sync.
// Esc counts as "Just the page" so the prompt doesn't come back.
export default class extends Controller {
  static targets = ["row", "check", "filter", "count", "submit", "none", "dismiss"]

  connect() {
    this.count()
    if (!this.element.open) this.element.showModal()
  }

  dismiss(event) {
    event.preventDefault()
    this.dismissTarget.click()
  }

  filter() {
    const query = this.filterTarget.value.trim().toLowerCase()
    let shown = 0
    this.rowTargets.forEach((row) => {
      row.hidden = query !== "" && !row.dataset.search.includes(query)
      if (!row.hidden) shown++
    })
    this.noneTarget.hidden = shown > 0
  }

  selectVisible() {
    this.rowTargets.forEach((row) => {
      if (!row.hidden) row.querySelector("input[type=checkbox]").checked = true
    })
    this.count()
  }

  clear() {
    this.checkTargets.forEach((box) => { box.checked = false })
    this.count()
  }

  count() {
    const n = this.checkTargets.filter((box) => box.checked).length
    this.countTarget.textContent = n === 0 ? "None selected" : `${n} of ${this.checkTargets.length} selected`
    this.submitTarget.disabled = n === 0
    this.submitTarget.textContent = n === 0 ? "Pull selected" : `Pull ${n}`
  }
}
