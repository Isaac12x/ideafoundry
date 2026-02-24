import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "hidden", "urlInput", "labelInput", "empty"]

  connect() {
    this.links = JSON.parse(this.hiddenTarget.value || "[]")
    this.render()
  }

  add(event) {
    event.preventDefault()
    const url = this.urlInputTarget.value.trim()
    const label = this.labelInputTarget.value.trim()

    if (!url) return

    // Auto-prefix https if missing
    const finalUrl = url.match(/^https?:\/\//) ? url : `https://${url}`
    this.links.push({ url: finalUrl, label: label || this.extractDomain(finalUrl) })
    this.urlInputTarget.value = ""
    this.labelInputTarget.value = ""
    this.urlInputTarget.focus()
    this.sync()
  }

  remove(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.links.splice(index, 1)
    this.sync()
  }

  sync() {
    this.hiddenTarget.value = JSON.stringify(this.links)
    this.render()
  }

  render() {
    const chips = this.containerTarget
    chips.innerHTML = ""

    if (this.links.length === 0) {
      if (this.hasEmptyTarget) this.emptyTarget.style.display = ""
      return
    }

    if (this.hasEmptyTarget) this.emptyTarget.style.display = "none"

    this.links.forEach((link, i) => {
      const chip = document.createElement("span")
      chip.className = "backlog-link-chip"
      chip.innerHTML = `
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/></svg>
        <a href="${this.escapeHtml(link.url)}" target="_blank" rel="noopener" class="backlog-link-text">${this.escapeHtml(link.label || this.extractDomain(link.url))}</a>
        <button type="button" class="backlog-link-remove" data-action="click->backlog-links#remove" data-index="${i}">&times;</button>
      `
      chips.appendChild(chip)
    })
  }

  extractDomain(url) {
    try {
      return new URL(url).hostname.replace(/^www\./, "")
    } catch {
      return url
    }
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
