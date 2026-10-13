import { Controller } from "@hotwired/stimulus"

// Project page behaviours: autosave of inline fields, the private toggle
// (turning it off needs an explicit confirm) and repeatable measurement rows.
export default class extends Controller {
  submit(event) {
    event.currentTarget.form?.requestSubmit()
  }

  async togglePrivate(event) {
    event.preventDefault()
    const button = event.currentTarget
    if (button.dataset.next === "0") {
      const confirmed = await window.AppDialog?.confirm(
        "AI jobs, agent tools and extraction will be able to read everything in this project.",
        { title: "Make this project not private?", confirmLabel: "Make not private", variant: "danger" }
      )
      if (!confirmed) return
    }
    button.form.elements.private.value = button.dataset.next
    button.form.requestSubmit()
  }

  // Deleting a test removes its folder, every run and every attached file.
  async confirmDeleteTest(event) {
    const form = event.currentTarget
    if (form.dataset.confirmed === "1") return

    event.preventDefault()
    const runs = Number(form.dataset.runCount)
    const detail = runs ? ` and its ${runs === 1 ? "run" : `${runs} runs`}, with all attached files` : ""
    const confirmed = await window.AppDialog?.confirm(`Delete "${form.dataset.testName}"${detail}?`, {
      title: "Delete test?", confirmLabel: "Delete", variant: "danger"
    })
    if (!confirmed) return
    form.dataset.confirmed = "1"
    form.requestSubmit()
  }

  addMeasure(event) {
    const set = event.currentTarget.closest("fieldset")
    const row = set.querySelector("template").content.cloneNode(true)
    set.querySelector(".kbp-measure-rows").appendChild(row)
    set.querySelector(".kbp-measure-rows .kbp-measure:last-child input")?.focus()
  }

  removeMeasure(event) {
    const row = event.currentTarget.closest(".kbp-measure")
    const rows = row.parentElement
    row.remove()
    if (!rows.children.length) rows.closest("fieldset").querySelector("[data-action~='kb-project#addMeasure']").click()
  }
}
