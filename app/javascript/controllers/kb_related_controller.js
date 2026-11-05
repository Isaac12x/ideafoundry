import { Controller } from "@hotwired/stimulus"

// Entry picker for the file header's Related popover: search KB entries, click one to link it.
export default class extends Controller {
  static targets = ["details", "form", "input", "results", "peerSrc", "peerPath"]
  static values = { searchUrl: String }

  opened() {
    if (this.detailsTarget.open) this.inputTarget.focus()
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetch(this.inputTarget.value.trim()), 200)
  }

  async _fetch(query) {
    if (!query) return this._render([])
    try {
      const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" } })
      this._render((await response.json()).results || [])
    } catch {
      this._render([])
    }
  }

  _render(results) {
    const list = this.resultsTarget
    list.replaceChildren(...results.filter((r) => r.type !== "project").map((entry) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.setAttribute("role", "option")
      button.textContent = `${entry.path}${entry.type === "dir" ? "/" : ""}`
      button.title = entry.source
      button.addEventListener("click", () => this.pick(entry))
      item.append(button)
      return item
    }))
    list.hidden = !list.children.length
  }

  pick(entry) {
    this.peerSrcTarget.value = entry.src
    this.peerPathTarget.value = entry.path
    this.formTarget.requestSubmit()
  }
}
