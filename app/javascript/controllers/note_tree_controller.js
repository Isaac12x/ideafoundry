import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["node", "replyForm", "children", "thread", "collapseLabel"]

  toggleReply(event) {
    const noteId = event.params.noteId
    const form = this.replyFormTargets.find(f => f.dataset.noteId === String(noteId))
    if (!form) return

    const isVisible = form.style.display !== "none"
    // Hide all open reply forms first
    this.replyFormTargets.forEach(f => f.style.display = "none")

    if (!isVisible) {
      form.style.display = "block"
      const input = form.querySelector(".note-form-input")
      if (input) input.focus()
    }
  }

  toggleCollapse(event) {
    const noteId = event.params.noteId
    const thread = this.threadTargets.find(t => t.dataset.noteId === String(noteId))
    const label = this.collapseLabelTargets.find(l => l.dataset.noteId === String(noteId))
    const btn = event.currentTarget

    if (!thread) return

    const isCollapsed = thread.classList.contains("note-thread--collapsed")

    if (isCollapsed) {
      thread.classList.remove("note-thread--collapsed")
      btn.classList.remove("note-collapse-btn--collapsed")
      if (label) label.textContent = label.textContent.replace("Show ", "")
    } else {
      thread.classList.add("note-thread--collapsed")
      btn.classList.add("note-collapse-btn--collapsed")
      if (label) label.textContent = "Show " + label.textContent
    }
  }
}
