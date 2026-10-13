import { Controller } from "@hotwired/stimulus"

// Inline combobox: search KB entries, pick one to POST a link (Turbo stream response).
export default class extends Controller {
  static targets = ["input", "list"]
  static values = { searchUrl: String, createUrl: String }

  disconnect() { clearTimeout(this.timer) }

  search() {
    clearTimeout(this.timer)
    const q = this.inputTarget.value.trim()
    if (!q) return this.close()
    this.timer = setTimeout(async () => {
      const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
      if (!response.ok || this.inputTarget.value.trim() !== q) return
      this.render((await response.json()).results)
    }, 150)
  }

  render(results) {
    this.results = results
    this.active = results.length ? 0 : -1
    this.listTarget.replaceChildren(...results.map((r, i) => {
      const li = document.createElement("li")
      li.id = `${this.listTarget.id}_${i}`
      li.setAttribute("role", "option")
      li.dataset.index = i
      li.className = "idea-kb-links__option"
      const glyph = { project: "◆", dir: "▸", file: "▫" }[r.type]
      li.textContent = `${glyph} ${r.name}`
      const meta = document.createElement("small")
      meta.textContent = ` ${r.source}/${r.path}`
      li.append(meta)
      li.addEventListener("mousedown", (event) => { event.preventDefault(); this.pick(i) })
      return li
    }))
    if (!results.length) {
      const li = document.createElement("li")
      li.className = "idea-kb-links__option is-empty"
      li.textContent = "No matches"
      this.listTarget.replaceChildren(li)
    }
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.highlight()
  }

  keydown(event) {
    if (this.listTarget.hidden || !this.results?.length) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.active = (this.active + step + this.results.length) % this.results.length
      this.highlight()
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (this.active >= 0) this.pick(this.active)
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  highlight() {
    this.listTarget.querySelectorAll("[role=option]").forEach((li, i) => {
      li.setAttribute("aria-selected", i === this.active ? "true" : "false")
    })
    const current = this.listTarget.children[this.active]
    if (current && this.active >= 0) {
      this.inputTarget.setAttribute("aria-activedescendant", current.id)
      current.scrollIntoView({ block: "nearest" })
    }
  }

  async pick(index) {
    const r = this.results[index]
    const body = new URLSearchParams({ src: r.src, path: r.path })
    const response = await fetch(this.createUrlValue, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body
    })
    if (response.ok) window.Turbo.renderStreamMessage(await response.text())
    this.close()
  }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
