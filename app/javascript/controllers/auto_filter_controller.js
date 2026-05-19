import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "search"]

  submit() {
    this.formTarget.requestSubmit()
  }

  debouncedSubmit() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this.submit(), 400)
  }
}
