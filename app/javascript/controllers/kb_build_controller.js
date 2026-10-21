import { Controller } from "@hotwired/stimulus"

// Build-plan checklist. Rows are plain server-rendered fields; every submit
// serializes them into the hidden `items` JSON (the server validates it all).
// Changes autosave by submitting the form; the page re-renders afterwards, so
// the field to refocus is carried across the disconnect/connect.
let pending = null // { id, field, at }

export default class extends Controller {
  static targets = ["field", "row", "add"]

  connect() {
    if (!pending || Date.now() - pending.at > 5000) return

    const row = pending.id && this.rowTargets.find((r) => r.dataset.id === pending.id)
    const target = row ? row.querySelector(pending.field) : this.addTarget
    target?.focus({ preventScroll: true })
    pending = null
  }

  items() {
    const items = this.rowTargets.map((row) => {
      const value = (name) => row.querySelector(`[data-field="${name}"]`).value
      return { id: row.dataset.id, title: value("title"), status: value("status"), note: value("note"), links: value("links") }
    })
    const title = this.addTarget.value.trim()
    if (title) items.push({ title, status: "todo" })
    return items
  }

  // submit: runs before Turbo sends the form.
  sync() {
    this.fieldTarget.value = JSON.stringify(this.items())
    const active = document.activeElement
    const row = active?.closest?.('[data-kb-build-target="row"]')
    if (!pending && row && active.dataset.field) pending = { id: row.dataset.id, field: `[data-field="${active.dataset.field}"]`, at: Date.now() }
  }

  // change: autosave edited rows. The add field only submits on Enter / Add.
  save(event) {
    if (event.target === this.addTarget) return
    this.element.requestSubmit()
  }

  click(event) {
    const button = event.target.closest("button[data-move], button[data-remove]")
    if (!button) return

    const row = button.closest('[data-kb-build-target="row"]')
    if (button.hasAttribute("data-remove")) {
      row.remove()
      pending = { id: null, at: Date.now() }
    } else {
      const sibling = Number(button.dataset.move) < 0 ? row.previousElementSibling : row.nextElementSibling
      if (!sibling) return
      if (Number(button.dataset.move) < 0) sibling.before(row)
      else sibling.after(row)
      pending = { id: row.dataset.id, field: `[data-move="${button.dataset.move}"]`, at: Date.now() }
    }
    this.element.requestSubmit()
  }
}
