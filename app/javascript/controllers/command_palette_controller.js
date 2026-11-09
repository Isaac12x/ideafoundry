import { Controller } from "@hotwired/stimulus"
import { binding, matches, isMac } from "lib/shortcut_bindings"

export default class extends Controller {
  static values = { searchUrl: String }
  static targets = ["input", "results", "key"]

  connect() {
    this._timer = null
    this._selectedIndex = -1
    this._boundKeydown = this._globalKeydown.bind(this)
    this._boundOpen = () => this.open()
    document.addEventListener("keydown", this._boundKeydown)
    document.addEventListener("command-palette:open", this._boundOpen)
    this._showHint()
    this.keyTargets.forEach((el) => { el.textContent = binding("search") })
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown)
    document.removeEventListener("command-palette:open", this._boundOpen)
    clearTimeout(this._timer)
  }

  _globalKeydown(e) {
    // Cmd+P (Mac) / Ctrl+P: the palette instead of the print dialog, even inside inputs.
    const mod = isMac() ? e.metaKey && !e.ctrlKey : e.ctrlKey && !e.metaKey
    if ((mod && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "p") || matches(binding("search"), e)) {
      e.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.element.open) return

    this.element.showModal()
    this.inputTarget.focus()
    this.inputTarget.select()
    this._showHint()
  }

  close() {
    this.element.close()
  }

  onCancel() {
    this._reset()
  }

  backdropClick(e) {
    if (e.target === this.element) this.close()
  }

  search() {
    clearTimeout(this._timer)
    const q = this.inputTarget.value.trim()
    if (!q) { this._showHint(); return }
    this._render(this._actions(q))
    this._timer = setTimeout(() => this._fetch(q), 200)
  }

  navigate(e) {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp" && e.key !== "Enter") return

    const items = this.resultsTarget.querySelectorAll(".cp-result")
    if (!items.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._selectedIndex = Math.min(this._selectedIndex + 1, items.length - 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const idx = this._selectedIndex >= 0 ? this._selectedIndex : 0
      const url = items[idx]?.dataset.url
      if (url) { this.close(); this._visit(url) }
      return
    }

    items.forEach((el, i) => el.classList.toggle("cp-result--active", i === this._selectedIndex))
    items[this._selectedIndex]?.scrollIntoView({ block: "nearest" })
  }

  async _fetch(q) {
    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", q)
      const resp = await fetch(url, { headers: { Accept: "application/json" } })
      if (!resp.ok) throw new Error(resp.status)
      const { groups } = await resp.json()
      if (!this.hasInputTarget || this.inputTarget.value.trim() !== q) return // stale response
      this._render([...this._actions(q), ...(groups || [])])
    } catch { /* silently fail */ }
  }

  // Navigation and "new" actions reuse the URLs the layout already puts on <body> for the keyboard shortcuts.
  _actions(q = "") {
    const d = document.body.dataset
    const all = [
      ["Ideas", "Ideas"], ["Plan", "Plan"], ["Intake", "Intake"], ["Topologies", "Topologies"], ["Licensing", "Licensing"],
      ["Knowledge Base", "Kb"], ["Backlog", "Backlog"], ["Settings", "Settings"],
      ["New idea", "NewIdea"], ["New named list", "NewList"], ["New topology", "NewTopology"], ["Import submissions", "Import"]
    ]
    const items = all.map(([title, key]) => ({ title, hint: title.startsWith("New") || title.startsWith("Import") ? "action" : "go to", url: d[`shortcuts${key}UrlValue`] }))
      .filter((i) => i.url && i.title.toLowerCase().includes(q.toLowerCase()))
    return items.length ? [{ label: "Actions", items }] : []
  }

  _render(groups) {
    this._selectedIndex = -1

    if (!groups.length) {
      this.resultsTarget.innerHTML = `<p class="cp-empty">No results</p>`
      return
    }

    const frag = document.createDocumentFragment()
    groups.forEach((group) => {
      const h = document.createElement("p")
      h.className = "cp-group"
      h.textContent = group.label
      frag.appendChild(h)
      group.items.forEach((item) => {
        const a = document.createElement("a")
        a.className = "cp-result"
        a.href = item.url
        a.dataset.url = item.url
        a.innerHTML = `
          <div class="cp-result-main">
            <span class="cp-result-title">${this._esc(item.title)}</span>
            ${item.hint ? `<span class="cp-result-state">${this._esc(item.hint)}</span>` : ""}
          </div>`
        a.addEventListener("click", (e) => {
          e.preventDefault()
          this.close()
          this._visit(item.url)
        })
        frag.appendChild(a)
      })
    })

    this.resultsTarget.replaceChildren(frag)
    this._selectedIndex = 0
    this.resultsTarget.querySelector(".cp-result")?.classList.add("cp-result--active")
  }

  _showHint() {
    this._render(this._actions())
  }

  _reset() {
    this.inputTarget.value = ""
    this._showHint()
  }

  _visit(url) {
    if (typeof Turbo !== "undefined") {
      Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
