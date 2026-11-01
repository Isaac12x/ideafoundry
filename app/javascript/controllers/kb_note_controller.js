import { Controller } from "@hotwired/stimulus"
import { binding, matches } from "lib/shortcut_bindings"
import { splitStamps, stampFor } from "lib/kb_clip_time"
import { hasFieldDraft, restoreFieldDraft } from "lib/field_draft"

// "Why I saved this" note above a KB file. Reads/writes the sidecar "<file>.note.md"
// through KbNotesController: click the toggle to read or start writing, Ctrl/Cmd+Enter saves, Esc cancels.
// On a video/audio page "Stamp time" drops the playback time ("[1:23]") into the note and a stamp in the saved
// note is a button that seeks the player.
// ponytail: no single-key shortcut; "n" belongs to the global "n i / n l" sequences.
export default class extends Controller {
  static targets = ["view", "toggle", "panel", "preview", "edit", "form", "input", "status", "more", "stamp"]
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
      if (hasFieldDraft(this.inputTarget)) this.edit() // unsaved text from before a lock or reload: reopen the editor on it
      if (!this.gone) this.element.hidden = false
      this.clamp()
    } catch {
      // leave the panel hidden; the file itself still opens
    }
  }

  show(data) {
    this.text = data.text || ""
    this.viewTarget.innerHTML = data.html || ""
    this.linkStamps()
    this.viewTarget.hidden = !this.text
    this.editTarget.hidden = !this.text
    this.formTarget.hidden = true
    this.previewTarget.textContent = this.firstLine() || "Add note"
    this.clamp()
  }

  // First line of the note, markdown marks stripped, for the collapsed toggle (CSS ellipsis does the clipping).
  firstLine() {
    return this.text.split("\n").map((line) => line.replace(/^[#>*\s-]+|[*_`]/g, "").trim()).find(Boolean) || ""
  }

  // Collapsed by default; an empty note opens straight into the editor.
  toggle() {
    if (!this.panelTarget.hidden) return this.setOpen(false)
    this.setOpen(true)
    if (!this.text) this.edit()
  }

  setOpen(open) {
    this.panelTarget.hidden = !open
    this.toggleTarget.setAttribute("aria-expanded", String(open))
    if (open) this.clamp()
  }

  media() { return this.element.closest(".kb-document")?.querySelector("video, audio") }

  // "[1:23]" in the rendered note -> button that seeks. Skips links and code.
  linkStamps() {
    if (!this.media()) return
    const texts = []
    const walker = document.createTreeWalker(this.viewTarget, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (/\[\d+:\d{2}/.test(node.nodeValue) && !node.parentElement.closest("a, code, pre")) texts.push(node)
    }
    texts.forEach((node) => node.replaceWith(...splitStamps(node.nodeValue).map((part) => {
      if (typeof part === "string") return part
      const button = Object.assign(document.createElement("button"), { type: "button", className: "kb-note__time", textContent: part.label })
      button.dataset.seconds = part.seconds
      button.title = "Jump to this time"
      return button
    })))
  }

  seekStamp(event) {
    const button = event.target.closest("[data-seconds]")
    const media = this.media()
    if (!button || !media) return
    media.currentTime = Number(button.dataset.seconds)
    media.play?.()
  }

  stamp() {
    const media = this.media()
    if (!media) return
    const field = this.inputTarget
    const text = `${stampFor(media.currentTime)} `
    field.setRangeText(text, field.selectionStart, field.selectionEnd, "end")
    field.dispatchEvent(new Event("input", { bubbles: true })) // autosize + draft keeper
    field.focus()
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

  async edit() {
    this.inputTarget.value = this.text
    this.setOpen(true)
    this.viewTarget.hidden = this.editTarget.hidden = true
    this.formTarget.hidden = false
    this.statusTarget.textContent = ""
    this.stampTarget.hidden = !this.media()
    this.inputTarget.focus()
    if (await restoreFieldDraft(this.inputTarget, { force: true })) this.statusTarget.textContent = "Draft restored. Cancel discards it."
  }

  clearDraft() {
    this.inputTarget.dispatchEvent(new CustomEvent("draft:clear", { bubbles: true }))
  }

  cancel() {
    this.clearDraft()
    this.show({ text: this.text, html: this.viewTarget.innerHTML })
    if (!this.text) this.setOpen(false)
    ;(this.text ? this.editTarget : this.toggleTarget).focus()
  }

  key(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    } else if (matches(binding("submit"), event)) {
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
      this.clearDraft()
      if (!this.text) this.setOpen(false)
      ;(this.text ? this.editTarget : this.toggleTarget).focus()
      this.statusTarget.textContent = "Saved"
      this.savedTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
    } catch (error) {
      this.statusTarget.textContent = error.message
    }
  }
}
