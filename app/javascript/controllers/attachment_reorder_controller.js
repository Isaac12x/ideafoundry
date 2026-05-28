import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "status", "list"]
  static values = { url: String }

  connect() {
    this.dragged = null
    this.sync()
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

  appendItems(event) {
    const { html } = event.detail
    if (!html) return
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    Array.from(template.content.children).forEach(item => {
      const list = this._listForKind(this._kindForItem(item))
      if (list) list.appendChild(item)
    })
    this.sync()
  }

  sync() {
    this._moveItemsToMatchingSections()
    this._syncSectionCounts()
    this._syncEmptyStates()
  }

  async destroyItem(event) {
    const item = event.currentTarget.closest("[data-attachment-reorder-target='item']")
    if (!item) return
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(item.dataset.destroyUrl, {
      method: "DELETE",
      headers: { "X-CSRF-Token": token, "Accept": "application/json" }
    })
    if (response.ok || response.status === 204) item.remove()
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

  _moveItemsToMatchingSections() {
    this.itemTargets.forEach(item => {
      const kind = this._kindForItem(item)
      const list = this._listForKind(kind)
      if (list && item.parentElement !== list) list.appendChild(item)
    })
  }

  _syncSectionCounts() {
    this.element.querySelectorAll("[data-attachment-list]").forEach(list => {
      const count = list.querySelectorAll("[data-attachment-id]").length
      const headerCount = list.closest(".current-attachments__section")?.querySelector(".current-attachments__section-header span")
      if (headerCount) headerCount.textContent = count
    })
  }

  _syncEmptyStates() {
    this.element.querySelectorAll("[data-attachment-empty]").forEach(empty => {
      const list = this._listForKind(empty.dataset.attachmentEmpty)
      empty.hidden = !!list?.querySelector("[data-attachment-id]")
    })
  }

  _listForKind(kind) {
    return this.element.querySelector(`[data-attachment-list="${kind}"]`)
  }

  _kindForItem(item) {
    if (item.dataset.attachmentKind) return item.dataset.attachmentKind
    return item.dataset.contentType?.startsWith("image/") ? "image" : "document"
  }
}
