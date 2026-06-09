import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  connect() {
    this.dragItem = null
  }

  itemTargetConnected(el) {
    if (el.getAttribute("draggable") === "true") {
      el.addEventListener("dragstart", this.onDragStart.bind(this))
      el.addEventListener("dragend", this.onDragEnd.bind(this))
      el.addEventListener("dragover", this.onDragOver.bind(this))
      el.addEventListener("drop", this.onDrop.bind(this))
    }
  }

  onDragStart(e) {
    this.dragItem = e.currentTarget
    e.currentTarget.classList.add("dragging")
    e.dataTransfer.effectAllowed = "move"
  }

  onDragEnd(e) {
    e.currentTarget.classList.remove("dragging")
    this.itemTargets.forEach(el => el.classList.remove("drag-over"))
    this.dragItem = null
  }

  onDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    this.itemTargets.forEach(el => el.classList.remove("drag-over"))
    if (e.currentTarget !== this.dragItem) {
      e.currentTarget.classList.add("drag-over")
    }
  }

  onDrop(e) {
    e.preventDefault()
    const target = e.currentTarget
    if (target === this.dragItem) return

    const items = [...this.itemTargets]
    const fromIdx = items.indexOf(this.dragItem)
    const toIdx = items.indexOf(target)

    if (fromIdx < toIdx) {
      target.after(this.dragItem)
    } else {
      target.before(this.dragItem)
    }

    this.saveOrder()
  }

  saveOrder() {
    const order = this.itemTargets.map(el => el.dataset.itemId)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ order })
    })
  }
}
