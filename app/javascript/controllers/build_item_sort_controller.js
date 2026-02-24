import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  connect() {
    this.setupDragAndDrop()
  }

  setupDragAndDrop() {
    this.itemTargets.forEach(item => {
      if (item.draggable) {
        item.addEventListener("dragstart", this.handleDragStart.bind(this))
        item.addEventListener("dragend", this.handleDragEnd.bind(this))
      }
    })
    this.element.addEventListener("dragover", this.handleDragOver.bind(this))
    this.element.addEventListener("drop", this.handleDrop.bind(this))
  }

  itemTargetConnected(element) {
    if (element.draggable) {
      element.addEventListener("dragstart", this.handleDragStart.bind(this))
      element.addEventListener("dragend", this.handleDragEnd.bind(this))
    }
  }

  handleDragStart(event) {
    this.draggedElement = event.currentTarget
    event.currentTarget.classList.add("dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", event.currentTarget.dataset.itemId)
  }

  handleDragEnd(event) {
    event.currentTarget.classList.remove("dragging")
    this.draggedElement = null
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const afterElement = this.getDragAfterElement(event.clientY)
    if (afterElement) {
      this.element.insertBefore(this.draggedElement, afterElement)
    } else {
      const lastItem = this.itemTargets[this.itemTargets.length - 1]
      if (lastItem && lastItem !== this.draggedElement) {
        lastItem.after(this.draggedElement)
      }
    }
  }

  handleDrop(event) {
    event.preventDefault()
    this.saveOrder()
  }

  getDragAfterElement(y) {
    const items = this.itemTargets.filter(el => el !== this.draggedElement)
    return items.reduce((closest, child) => {
      const box = child.getBoundingClientRect()
      const offset = y - box.top - box.height / 2
      if (offset < 0 && offset > closest.offset) {
        return { offset, element: child }
      }
      return closest
    }, { offset: Number.NEGATIVE_INFINITY }).element
  }

  async saveOrder() {
    const order = this.itemTargets.map(el => el.dataset.itemId)
    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ order })
    })
  }
}
