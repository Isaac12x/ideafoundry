import { Controller } from "@hotwired/stimulus"

// <details> groups that remember which ones are collapsed (localStorage, per key).
export default class extends Controller {
  static targets = ["group"]
  static values = { key: String }

  connect() {
    const closed = this.closed()
    this.groupTargets.forEach((g) => { if (closed.includes(g.dataset.groupId)) g.open = false })
  }

  save() {
    const closed = this.groupTargets.filter((g) => !g.open).map((g) => g.dataset.groupId)
    try { localStorage.setItem(this.keyValue, JSON.stringify(closed)) } catch (_e) { /* private mode */ }
  }

  closed() {
    try { return JSON.parse(localStorage.getItem(this.keyValue)) || [] } catch (_e) { return [] }
  }
}
