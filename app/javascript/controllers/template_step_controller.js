import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "form"]
  static values = {
    selected: { type: Boolean, default: false }
  }

  connect() {
    if (this.selectedValue) {
      this._showForm()
    } else if (this.hasStepTarget) {
      this._showStep()
    } else {
      this._showForm()
    }
  }

  select(event) {
    event.preventDefault()
    const templateId = event.currentTarget.dataset.templateId
    const selector = this.element.querySelector("[data-template-switch-target='selector']")
    if (selector) {
      selector.value = templateId
      selector.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this._showForm()
  }

  skip(event) {
    event.preventDefault()
    const selector = this.element.querySelector("[data-template-switch-target='selector']")
    if (selector) {
      selector.value = ""
      selector.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this._showForm()
  }

  _showStep() {
    if (this.hasStepTarget) this.stepTarget.style.display = ""
    if (this.hasFormTarget) this.formTarget.style.display = "none"
  }

  _showForm() {
    if (this.hasStepTarget) this.stepTarget.style.display = "none"
    if (this.hasFormTarget) this.formTarget.style.display = ""
  }
}
