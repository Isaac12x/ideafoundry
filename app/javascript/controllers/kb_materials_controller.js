import { Controller } from "@hotwired/stimulus"

const NONE = "__none__"

// Client-side stage + text filter over materials and tests. The chosen stage
// is remembered per project in sessionStorage (best effort).
export default class extends Controller {
  static targets = ["chip", "item", "group", "query", "none"]
  static values = { key: String }

  connect() {
    this.filter = this.read() || "all"
    this.apply()
  }

  pick(event) {
    this.filter = event.currentTarget.dataset.filter
    this.write(this.filter)
    this.apply()
  }

  apply() {
    const q = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()
    this.chipTargets.forEach((chip) => {
      const on = chip.dataset.filter === this.filter
      chip.classList.toggle("is-on", on)
      chip.setAttribute("aria-pressed", String(on))
    })
    let shown = 0
    this.itemTargets.forEach((item) => {
      const stage = item.dataset.stage || ""
      const stageOk = this.filter === "all" || (this.filter === NONE ? stage === "" : stage === this.filter)
      const ok = stageOk && (!q || (item.dataset.search || "").includes(q))
      item.hidden = !ok
      if (ok) shown++
    })
    const filtering = this.filter !== "all" || q !== ""
    this.groupTargets.forEach((group) => {
      const items = [...group.querySelectorAll("[data-kb-materials-target~='item']")]
      const visible = items.filter((i) => !i.hidden).length
      const count = group.querySelector("[data-count]")
      if (count) count.textContent = filtering && items.length ? `${visible}/${items.length}` : String(items.length)
      group.hidden = filtering && items.length > 0 && visible === 0
    })
    if (this.hasNoneTarget) this.noneTarget.hidden = !(filtering && shown === 0)
  }

  read() {
    try { return sessionStorage.getItem(`kbp-filter:${this.keyValue}`) } catch { return null }
  }

  write(value) {
    try { sessionStorage.setItem(`kbp-filter:${this.keyValue}`, value) } catch { /* private mode */ }
  }
}
