import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "status"]
  static values = { url: String }

  connect() {
    this.dragged = null
  }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.attachmentId)
    this.dragged.classList.add("current-attachments__item--dragging")
  }

  dragEnd() {
    if (this.dragged) this.dragged.classList.remove("current-attachments__item--dragging")
    this.dragged = null
  }

  dragOver(event) {
    event.preventDefault()
    const target = event.currentTarget
    if (!this.dragged || target === this.dragged) return

    const rect = target.getBoundingClientRect()
    const after = event.clientY > rect.top + rect.height / 2
    target.parentNode.insertBefore(this.dragged, after ? target.nextSibling : target)
  }

  moveUp(event) {
    const item = event.currentTarget.closest("[data-attachment-reorder-target='item']")
    if (item?.previousElementSibling) item.parentNode.insertBefore(item, item.previousElementSibling)
    this.persist()
  }

  moveDown(event) {
    const item = event.currentTarget.closest("[data-attachment-reorder-target='item']")
    if (item?.nextElementSibling) item.parentNode.insertBefore(item.nextElementSibling, item)
    this.persist()
  }

  drop(event) {
    event.preventDefault()
    this.persist()
  }

  async persist() {
    if (!this.hasUrlValue) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams()
    this.itemTargets.forEach(item => body.append("attachment_ids[]", item.dataset.attachmentId))

    this._setStatus("Saving attachment order…")
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": token,
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body
    })

    this._setStatus(response.ok ? "Attachment order saved." : "Could not save attachment order.")
  }

  _setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
