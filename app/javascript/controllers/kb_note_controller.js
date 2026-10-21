import { Controller } from "@hotwired/stimulus"

// "Why I saved this" note above a KB file. Reads/writes the sidecar "<file>.note.md"
// through KbNotesController: click to start writing, Ctrl/Cmd+Enter saves, Esc cancels.
// ponytail: no single-key shortcut; "n" belongs to the global "n i / n l" sequences.
export default class extends Controller {
  static targets = ["view", "empty", "edit", "form", "input", "status", "more"]
  static values = { url: String }

  connect() {
    this.text = ""
    this.load()
  }

  disconnect() {
    this.gone = true
    clearTimeout(this.savedTimer)
  }

  async load() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return // not a note-capable file: stay hidden
      this.show(await response.json())
      if (!this.gone) this.element.hidden = false
      this.clamp()
    } catch {
      // leave the panel hidden; the file itself still opens
    }
  }

  show(data) {
    this.text = data.text || ""
    this.viewTarget.innerHTML = data.html || ""
    this.viewTarget.hidden = !this.text
    this.editTarget.hidden = !this.text
    this.emptyTarget.hidden = !!this.text
    this.formTarget.hidden = true
    this.clamp()
  }

  // Long notes show ~3 lines; "more" expands in place.
  toggleMore() {
    this.element.classList.toggle("kb-note--open")
    this.clamp()
  }

  clamp() {
    const open = this.element.classList.contains("kb-note--open")
    this.moreTarget.textContent = open ? "less" : "more"
    this.moreTarget.setAttribute("aria-expanded", open)
    this.moreTarget.hidden = this.viewTarget.hidden || !(open || this.viewTarget.scrollHeight > this.viewTarget.clientHeight + 1)
  }

  edit() {
    this.inputTarget.value = this.text
    this.viewTarget.hidden = this.editTarget.hidden = this.emptyTarget.hidden = true
    this.formTarget.hidden = false
    this.statusTarget.textContent = ""
    this.inputTarget.focus()
  }

  cancel() {
    this.show({ text: this.text, html: this.viewTarget.innerHTML })
    ;(this.text ? this.editTarget : this.emptyTarget).focus()
  }

  key(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    } else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  async save(event) {
    event.preventDefault()
    this.statusTarget.textContent = "Saving…"
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? ""
        },
        body: JSON.stringify({ text: this.inputTarget.value })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Couldn't save the note.")
      this.show(data)
      ;(this.text ? this.editTarget : this.emptyTarget).focus()
      this.statusTarget.textContent = "Saved"
      this.savedTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
    } catch (error) {
      this.statusTarget.textContent = error.message
    }
  }
}
