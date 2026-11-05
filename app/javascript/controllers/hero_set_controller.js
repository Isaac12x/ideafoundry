import { Controller } from "@hotwired/stimulus"

// Hero tile list in the idea form. Order is the DOM order of each tile's hidden
// idea[hero_order][] input, so drag and the arrow buttons only move <li>s.
// Image removal is deferred: it adds idea[remove_hero_image_ids][] and the save purges.
export default class extends Controller {
  static targets = ["list", "empty", "item"]

  connect() {
    this._observer = new MutationObserver(() => this._refresh())
    this._observer.observe(this.listTarget, { childList: true })
    this._refresh()
  }

  disconnect() {
    this._observer?.disconnect()
  }

  earlier(event) { this._move(event, -1) }
  later(event) { this._move(event, 1) }

  removeImage(event) {
    const btn = event.currentTarget
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "idea[remove_hero_image_ids][]"
    input.value = btn.dataset.blobId
    this.element.appendChild(input)
    btn.closest("[data-hero-key]").remove()
  }

  dragStart(event) {
    this._dragging = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this._dragging.dataset.heroKey)
    requestAnimationFrame(() => this._dragging?.classList.add("hero-item--dragging"))
  }

  dragOver(event) {
    if (!this._dragging) return
    event.preventDefault()
    const target = event.currentTarget
    if (target === this._dragging) return
    const rect = target.getBoundingClientRect()
    const after = event.clientX > rect.left + rect.width / 2
    this.listTarget.insertBefore(this._dragging, after ? target.nextSibling : target)
  }

  drop(event) {
    if (this._dragging) event.preventDefault()
  }

  dragEnd() {
    this._dragging?.classList.remove("hero-item--dragging")
    this._dragging = null
  }

  _move(event, delta) {
    const item = event.currentTarget.closest("[data-hero-key]")
    const sibling = delta < 0 ? item.previousElementSibling : item.nextElementSibling
    if (!sibling) return
    this.listTarget.insertBefore(item, delta < 0 ? sibling : sibling.nextSibling)
    event.currentTarget.focus()
  }

  _refresh() {
    const items = Array.from(this.listTarget.children)
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", items.length > 0)
    items.forEach((li, i) => {
      li.querySelector("[aria-label='Move earlier']")?.toggleAttribute("disabled", i === 0)
      li.querySelector("[aria-label='Move later']")?.toggleAttribute("disabled", i === items.length - 1)
    })
  }
}
