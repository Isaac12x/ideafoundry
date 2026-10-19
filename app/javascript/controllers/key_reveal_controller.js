import { Controller } from "@hotwired/stimulus"

// Eye toggle for a key row. The key is fetched on demand (never in page HTML) and cleared on hide.
// Also copies a one-time token (data-key-reveal-text-value) or the fetched key.
export default class extends Controller {
  static targets = ["masked", "revealed", "button", "eye", "eyeOff", "copyLabel"]
  static values = { text: String, url: String }

  async toggle() {
    if (this.busy) return
    this.busy = true
    try {
      await this._toggle()
    } finally {
      this.busy = false
    }
  }

  async _toggle() {
    const show = this.revealedTarget.hidden
    if (show) {
      try {
        const res = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        if (!res.ok) throw new Error(res.status)
        const { token } = await res.json()
        this.textValue = token || ""
        this.revealedTarget.textContent = token || "Created before reveal was available — create a new key to view it, or this key can't be revealed"
      } catch {
        this.revealedTarget.textContent = "Could not load key"
        this.textValue = ""
      }
    } else {
      this.revealedTarget.textContent = ""
      this.textValue = ""
    }
    this.revealedTarget.hidden = !show
    this.maskedTarget.hidden = show
    this.eyeTarget.hidden = show
    this.eyeOffTarget.hidden = !show
    this.buttonTarget.setAttribute("aria-pressed", String(show))
    if (this.hasCopyLabelTarget) {
      this.copyLabelTarget.hidden = !(show && this.textValue)
      this.copyLabelTarget.textContent = "Copy"
    }
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.copyLabelTarget.textContent = "Copied"
    } catch {
      this.copyLabelTarget.textContent = "Copy failed"
    }
  }
}
