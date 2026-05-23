import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { upgradeUrl: String, statusUrl: String, healthUrl: String }

  async upgrade() {
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Upgrading…"

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.upgradeUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": token, "Accept": "application/json" }
    })

    this.pollStatus()
  }

  pollStatus() {
    const interval = setInterval(async () => {
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
    const interval = setInterval(async () => {
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
