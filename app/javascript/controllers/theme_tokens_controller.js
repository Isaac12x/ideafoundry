import { Controller } from "@hotwired/stimulus"

// Tokenized theme multi-select: existing themes are toggle chips, typing a new name + Enter
// adds a checked chip that the server creates on save. autoSubmit: save on every change (idea page).
export default class extends Controller {
  static targets = ["list", "input"]
  static values = { autoSubmit: Boolean }

  keydown(event) {
    if (event.key !== "Enter" && event.key !== ",") return
    event.preventDefault()
    const name = this.inputTarget.value.trim().replace(/\s+/g, " ")
    if (!name) return
    this.inputTarget.value = ""
    this.add(name)
    this.changed()
  }

  add(name) {
    const existing = [...this.listTarget.querySelectorAll("label")].find((l) => l.textContent.trim().toLowerCase() === name.toLowerCase())
    if (existing) {
      existing.querySelector("input").checked = true
      return this.announce(existing.querySelector("input"))
    }
    const label = document.createElement("label")
    label.className = "theme-chip"
    const box = Object.assign(document.createElement("input"), { type: "checkbox", name: "idea[new_theme_names][]", value: name, checked: true })
    const dot = Object.assign(document.createElement("span"), { className: "theme-chip__dot" })
    dot.setAttribute("aria-hidden", "true")
    label.append(box, dot, document.createTextNode(name))
    this.listTarget.append(label)
    this.announce(box)
  }

  // Draft restore: re-create the not-yet-saved theme chips (they have no server-rendered markup).
  restore(event) {
    if (!event.target.contains(this.element) || this.autoSubmitValue) return
    ;(event.detail.draft["idea[new_theme_names][]"] || []).forEach((name) => this.add(name))
  }

  changed() {
    if (this.autoSubmitValue) this.element.closest("form").requestSubmit()
  }

  announce(box) { // programmatic edits: let the draft saver see them
    box.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
