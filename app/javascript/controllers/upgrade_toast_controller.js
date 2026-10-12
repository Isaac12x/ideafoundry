import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { version: String, severity: String, settingsUrl: String }

  disconnect() {
    clearTimeout(this.timer)
  }

  connect() {
    const key = `upgrade_toast_first_seen_${this.versionValue}`
    const dismissKey = `upgrade_toast_dismissed_${this.versionValue}`

    let firstSeen
    try {
      if (localStorage.getItem(dismissKey)) return
      firstSeen = localStorage.getItem(key)
    } catch { return }
    const now = Date.now()
    const ttl = 300_000

    if (!firstSeen) {
      try { localStorage.setItem(key, now) } catch { /* storage unavailable */ }
      this.show()
    } else {
      const age = now - parseInt(firstSeen, 10)
      if (age < ttl) {
        this.show()
        this.timer = setTimeout(() => this.hide(), ttl - age)
      }
    }
  }

  show() {
    this.element.classList.add("upgrade-toast--visible")
  }

  hide() {
    this.element.classList.remove("upgrade-toast--visible")
  }

  dismiss() {
    try { localStorage.setItem(`upgrade_toast_dismissed_${this.versionValue}`, "1") } catch { /* storage unavailable */ }
    this.hide()
  }
}
