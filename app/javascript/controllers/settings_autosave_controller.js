import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async toggleChanged(event) {
    const form = event.target.closest("form")
    if (!form) return

    try {
      const response = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: {
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        }
      })

      const data = await response.json()
      this.showIndicator(response.ok ? "saved" : "error")
      if (response.ok && data.redirect_to) {
        window.location.href = data.redirect_to
      }
    } catch {
      this.showIndicator("error")
    }
  }

  // Live value next to a range: <output data-echo="<input id>"> (data-echo-scale / data-echo-unit on the input).
  echo(event) {
    const input = event.target
    const out = input.id && this.element.querySelector(`[data-echo="${input.id}"]`)
    if (!out) return
    const scale = Number(input.dataset.echoScale) || 1
    out.textContent = `${Math.round((Number(input.value) / scale) * 100) / 100}${input.dataset.echoUnit || ""}`
  }

  showIndicator(status) {
    let indicator = this.element.querySelector(".settings-autosave-indicator")
    if (!indicator) {
      indicator = document.createElement("div")
      indicator.className = "settings-autosave-indicator"
      this.element.appendChild(indicator)
    }
    indicator.className = `settings-autosave-indicator ${status}`
    indicator.textContent = status === "saved" ? "Saved" : "Save failed"
    clearTimeout(this._indicatorTimer)
    this._indicatorTimer = setTimeout(() => indicator.remove(), 2000)
  }
}
