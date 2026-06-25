import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String, joinUrl: String }

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
    this.clearJoinTarget()
    this.draggedElement = null
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    if (!this.draggedElement) return

    const over = event.target.closest(".backlog-item")
    // Hovering the central band of another item => join; edges/gaps => reorder.
    if (over && over !== this.draggedElement && this.isCenterBand(over, event.clientY)) {
      this.setJoinTarget(over)
      return
    }

    this.clearJoinTarget()
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
    if (this.joinTarget && this.draggedElement) {
      const sourceId = this.draggedElement.dataset.itemId
      const targetId = this.joinTarget.dataset.itemId
      this.clearJoinTarget()
      this.joinItems(sourceId, targetId)
    } else {
      this.saveOrder()
    }
  }

  isCenterBand(element, y) {
    const box = element.getBoundingClientRect()
    const offset = y - box.top
    return offset > box.height * 0.25 && offset < box.height * 0.75
  }

  setJoinTarget(element) {
    if (this.joinTarget === element) return
    this.clearJoinTarget()
    this.joinTarget = element
    element.classList.add("backlog-item--drop-target")
  }

  clearJoinTarget() {
    if (this.joinTarget) {
      this.joinTarget.classList.remove("backlog-item--drop-target")
      this.joinTarget = null
    }
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

  async joinItems(sourceId, targetId) {
    if (!this.hasJoinUrlValue || sourceId === targetId) return
    const response = await fetch(this.joinUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ source_id: sourceId, target_id: targetId })
    })
    if (!response.ok) return
    const html = await response.text()
    Turbo.renderStreamMessage(html)
  }
}
