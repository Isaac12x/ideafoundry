import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "section", "handle"]

  connect() {
    this._dragItem = null
    this.handleTargets.forEach((handle, i) => {
      const section = this.sectionTargets[i]
      handle.addEventListener("dragstart", (e) => this._onDragStart(e, section))
      handle.addEventListener("dragend", (e) => this._onDragEnd(e, section))
    })

    this.sectionTargets.forEach(section => {
      section.addEventListener("dragover", (e) => this._onDragOver(e, section))
      section.addEventListener("dragleave", () => section.classList.remove("drag-over"))
      section.addEventListener("drop", (e) => this._onDrop(e, section))
    })
  }

  _onDragStart(e, section) {
    this._dragItem = section
    section.classList.add("dragging")
    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", "")
  }

  _onDragEnd(e, section) {
    section.classList.remove("dragging")
    this.sectionTargets.forEach(s => s.classList.remove("drag-over"))
    this._dragItem = null
  }

  _onDragOver(e, section) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    if (section !== this._dragItem) {
      section.classList.add("drag-over")
    }
  }

  _onDrop(e, section) {
    e.preventDefault()
    section.classList.remove("drag-over")
    if (!this._dragItem || section === this._dragItem) return

    const container = this.containerTarget
    const rect = section.getBoundingClientRect()
    const midY = rect.top + rect.height / 2

    if (e.clientY < midY) {
      container.insertBefore(this._dragItem, section)
    } else {
      container.insertBefore(this._dragItem, section.nextSibling)
    }
  }
}
