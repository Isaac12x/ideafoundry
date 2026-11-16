import { Controller } from "@hotwired/stimulus"

// Polls enrichment_status while a scan runs, updates the step text, and reloads the tab when it settles.
export default class extends Controller {
  static targets = ["step"]
  static values = { statusUrl: String, state: String }

  connect() {
    if (this.stateValue === "running") this.timer = setInterval(() => this.poll(), 3000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    if (document.hidden) return
    try {
      const res = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      if (data.state === "running") {
        if (this.hasStepTarget && data.step) this.stepTarget.textContent = data.step
      } else {
        clearInterval(this.timer)
        window.Turbo.visit(`${window.location.pathname}#enrichment`, { action: "replace" })
      }
    } catch (_) { /* transient network error: try again next tick */ }
  }
}
