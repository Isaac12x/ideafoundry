import { Controller } from "@hotwired/stimulus"

const FIRST_FIELD = "textarea, input:not([type=hidden]):not([type=submit])"

// Shared by the quick-add forms (facts, maxims, problems). The server re-renders the form after each
// submit (blank on success, with the typed text + error on failure), so focus returns to the first field
// when the fresh form connects; a successful response also clears the fields at once.
export default class extends Controller {
  static values = { refocus: Boolean }

  connect() {
    if (this.refocusValue) this.element.querySelector(FIRST_FIELD)?.focus()
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  afterSubmit(event) {
    if (event.detail.success) {
      this.element.reset()
      this.element.querySelector(FIRST_FIELD)?.focus()
    }
  }
}
