import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { searchUrl: String }
  static targets = ["input", "results"]

  connect() {
    this._timer = null
    this._selectedIndex = -1
    this._boundKeydown = this._globalKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)
    this._showHint()
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown)
    clearTimeout(this._timer)
  }

  _globalKeydown(e) {
    const key = e.key.toLowerCase()
    if ((e.metaKey || e.ctrlKey) && (key === "k" || key === "p")) {
      e.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.element.open) return

    this.element.showModal()
    this.inputTarget.focus()
    this.inputTarget.select()
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
      const { results } = await resp.json()
      this._render(results)
    } catch { /* silently fail */ }
  }

  _render(results) {
    this._selectedIndex = -1

    if (!results.length) {
      this.resultsTarget.innerHTML = `<p class="cp-empty">No ideas found</p>`
      return
    }

    const frag = document.createDocumentFragment()
    results.slice(0, 8).forEach((idea) => {
      const a = document.createElement("a")
      a.className = "cp-result"
      a.href = idea.url
      a.dataset.url = idea.url

      const stateLabel = (idea.state || "").replace(/_/g, " ")
      const score = idea.score != null
        ? `<span class="cp-score">${Number(idea.score).toFixed(1)}</span>`
        : ""
      const snippet = idea.matches?.[0]?.snippet || ""

      a.innerHTML = `
        <div class="cp-result-main">
          <span class="cp-result-title">${this._esc(idea.title)}</span>
          ${score}
          <span class="cp-result-state idea-state ${this._esc(idea.state)}">${this._esc(stateLabel)}</span>
        </div>
        ${snippet ? `<div class="cp-result-snippet">${this._esc(snippet)}</div>` : ""}
      `

      a.addEventListener("click", (e) => {
        e.preventDefault()
        this.close()
        this._visit(idea.url)
      })

      frag.appendChild(a)
    })

    this.resultsTarget.replaceChildren(frag)
    this._selectedIndex = 0
    this.resultsTarget.querySelector(".cp-result")?.classList.add("cp-result--active")
  }

  _showHint() {
    this._selectedIndex = -1
    this.resultsTarget.innerHTML = `<p class="cp-hint">Type to search by title, summary or description</p>`
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
