import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { version: String, severity: String, settingsUrl: String }

  connect() {
    const key = `upgrade_toast_first_seen_${this.versionValue}`
    const dismissKey = `upgrade_toast_dismissed_${this.versionValue}`

    if (localStorage.getItem(dismissKey)) return

    const firstSeen = localStorage.getItem(key)
    const now = Date.now()
    const ttl = 300_000

    if (!firstSeen) {
      localStorage.setItem(key, now)
      this.show()
    } else {
      const age = now - parseInt(firstSeen, 10)
      if (age < ttl) {
        this.show()
        setTimeout(() => this.hide(), ttl - age)
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
    localStorage.setItem(`upgrade_toast_dismissed_${this.versionValue}`, "1")
    this.hide()
  }
}
