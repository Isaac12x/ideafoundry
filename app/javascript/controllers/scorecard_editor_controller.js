import { Controller } from "@hotwired/stimulus"

// Add/remove rows for user-defined scorecards. Ids are generated here so repeated
// autosaves of the same unsaved row stay idempotent on the server.
export default class extends Controller {
  static targets = ["list", "systemTemplate", "criterionTemplate"]

  hex() {
    return Array.from(crypto.getRandomValues(new Uint8Array(4)), (b) => b.toString(16).padStart(2, "0")).join("")
  }

  addSystem() {
    this.listTarget.insertAdjacentHTML("beforeend", this.systemTemplateTarget.innerHTML.replaceAll("__S__", this.hex()))
    const system = this.listTarget.lastElementChild
    system.querySelector("input[name$='[id]']").value = `custom_${this.hex()}`
    this.appendCriterion(system)
  }

  addCriterion(event) {
    this.appendCriterion(event.currentTarget.closest("[data-scorecard-editor-target='system']"))
  }

  appendCriterion(system) {
    const base = system.querySelector("input[name$='[id]']").name.replace(/\[id\]$/, "")
    const container = system.querySelector("[data-scorecard-editor-target='criteria']")
    container.insertAdjacentHTML("beforeend", this.criterionTemplateTarget.innerHTML.replaceAll("__BASE__", base).replaceAll("__C__", this.hex()))
    container.lastElementChild.querySelector("input[name$='[key]']").value = `c${this.hex()}`
  }

  removeSystem(event) {
    this.remove(event.currentTarget.closest("[data-scorecard-editor-target='system']"))
  }

  removeCriterion(event) {
    this.remove(event.currentTarget.closest("[data-scorecard-editor-target='criterion']"))
  }

  remove(node) {
    const form = node.closest("form")
    node.remove()
    form?.dispatchEvent(new Event("change", { bubbles: true })) // trigger settings autosave
  }
}
