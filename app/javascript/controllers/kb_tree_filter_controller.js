import { Controller } from "@hotwired/stimulus"

// Sidebar tree filter: an icon in the top row that expands an input inline. Esc closes and clears.
// Non-matching files and folders get .is-filtered-out; folders with a match stay and show their children
// (CSS), so nothing is lost from the collapsed state the tree remembers. The tree re-renders over Turbo, so
// the filter is re-applied after each render.
export default class extends Controller {
  static targets = ["toggle", "input"]

  connect() {
    this._observer = new MutationObserver(() => { if (this.query) this.apply() })
    const tree = this.element.closest(".kb-sidebar")
    if (tree) this._observer.observe(tree, { childList: true, subtree: true })
  }

  disconnect() {
    this._observer?.disconnect()
  }

  get query() {
    return this.inputTarget.value.trim().toLowerCase()
  }

  toggle() {
    if (this.inputTarget.hidden) this.open()
    else this.inputTarget.focus()
  }

  open() {
    this.inputTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.focus()
  }

  key(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    event.stopPropagation()
    this.close()
  }

  close() {
    this.inputTarget.value = ""
    this.apply()
    this.inputTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.toggleTarget.focus()
  }

  apply() {
    const query = this.query
    const tree = document.getElementById("kb-sidebar-tree")
    this.toggleTarget.classList.toggle("is-active", !!query) // visible cue that the tree is filtered
    if (!tree) return
    tree.classList.toggle("is-filtering", !!query)
    const label = (row) => (row.getAttribute("aria-label") || row.textContent).toLowerCase()
    tree.querySelectorAll(".kb-file-row").forEach((row) => row.classList.toggle("is-filtered-out", !!query && !label(row).includes(query)))
    // Deepest groups first so a parent sees its children's verdicts.
    const groups = [...tree.querySelectorAll(".kb-dir-group")].reverse()
    groups.forEach((group) => {
      const own = label(group.querySelector(":scope > .kb-dir-header")).includes(query)
      const kept = !query || own || group.querySelector(".kb-file-row:not(.is-filtered-out), .kb-dir-group:not(.is-filtered-out)")
      group.classList.toggle("is-filtered-out", !kept)
      // A folder whose own name matches keeps all its files.
      if (query && own) group.querySelectorAll(".kb-file-row, .kb-dir-group").forEach((el) => el.classList.remove("is-filtered-out"))
    })
  }
}
