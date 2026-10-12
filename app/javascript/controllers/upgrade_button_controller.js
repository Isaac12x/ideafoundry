import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { upgradeUrl: String, statusUrl: String, healthUrl: String }

  disconnect() {
    clearInterval(this.interval)
  }

  async upgrade() {
    const label = this.buttonTarget.textContent
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Upgrading…"

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch(this.upgradeUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" }
      })
      if (!res.ok) throw new Error(res.status)
    } catch {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = label
      return
    }

    this.pollStatus()
  }

  pollStatus() {
    clearInterval(this.interval)
    const interval = this.interval = setInterval(async () => {
      try {
        const res = await fetch(this.statusUrlValue, { headers: { "Accept": "application/json" } })
        if (!res.ok) throw new Error("gone")
      } catch {
        clearInterval(interval)
        this.pollHealth()
      }
    }, 3000)
  }

  pollHealth() {
    clearInterval(this.interval)
    const interval = this.interval = setInterval(async () => {
      try {
        const res = await fetch(this.healthUrlValue)
        if (res.ok) {
          clearInterval(interval)
          window.location.href = "/settings?upgraded=1"
        }
      } catch {
        // still restarting
      }
    }, 3000)
  }
}
