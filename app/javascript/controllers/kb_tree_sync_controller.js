import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (this.element.querySelector(".kb-async-row")) {
      this.timeout = window.setTimeout(() => this.refresh(), 1800)
    }
  }

  disconnect() {
    if (this.timeout) window.clearTimeout(this.timeout)
  }

  async refresh() {
    const active = document.querySelector(".kb-file-row.is-active")
    const url = new URL(this.urlValue, window.location.origin)
    if (active) {
      url.searchParams.set("sel_src", active.dataset.kbTreeSrcParam || "")
      url.searchParams.set("sel_file", active.dataset.kbTreeRelParam || "")
    }

    try {
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (!response.ok) throw new Error("Tree refresh failed")
      window.Turbo?.renderStreamMessage(await response.text())
    } catch (_error) {
      this.timeout = window.setTimeout(() => this.refresh(), 3000)
    }
  }
}
