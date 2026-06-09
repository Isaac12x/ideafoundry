import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    title: String,
    url: String,
    score: String,
    state: String,
    snippet: String
  }

  static targets = ["popover", "datetime"]

  connect() {
    const defaultDate = new Date()
    defaultDate.setDate(defaultDate.getDate() + 7)
    defaultDate.setHours(9, 0, 0, 0)
    const offset = defaultDate.getTimezoneOffset()
    const local = new Date(defaultDate.getTime() - offset * 60000)
    this.datetimeTarget.value = local.toISOString().slice(0, 16)
  }

  toggle() {
    this.popoverTarget.classList.toggle("hidden")
    const isOpen = !this.popoverTarget.classList.contains("hidden")
    this.element.querySelector("[data-action*='reminder#toggle']").setAttribute("aria-expanded", isOpen)
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.popoverTarget.classList.add("hidden")
      this.element.querySelector("[data-action*='reminder#toggle']").setAttribute("aria-expanded", "false")
    }
  }

  downloadIcs() {
    const dt = new Date(this.datetimeTarget.value)
    if (isNaN(dt)) return
    const end = new Date(dt.getTime() + 30 * 60000)
    const now = new Date()
    const title = this._escapeIcsText("Reminder: review idea " + this.titleValue)
    const description = [
      this._escapeIcsText(this.urlValue),
      "",
      "Score: " + this._escapeIcsText(this.scoreValue),
      "State: " + this._escapeIcsText(this.stateValue),
      "",
      this._escapeIcsText(this.snippetValue)
    ].join("\\n")

    const lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Idea Foundry//Reminder//EN",
      "BEGIN:VEVENT",
      `UID:${crypto.randomUUID()}@ideas.local`,
      `DTSTAMP:${this._formatDateUTC(now)}`,
      `DTSTART:${this._formatDateUTC(dt)}`,
      `DTEND:${this._formatDateUTC(end)}`,
      `SUMMARY:${title}`,
      `DESCRIPTION:${description}`,
      `URL:${this.urlValue}`,
      "BEGIN:VALARM",
      "TRIGGER:PT0M",
      "ACTION:DISPLAY",
      `DESCRIPTION:${title}`,
      "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    const ics = lines.map(l => this._foldIcsLine(l)).join("\r\n")

    const slug = this.titleValue.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 40)
    const blob = new Blob([ics], { type: "text/calendar" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `reminder-${slug || 'idea'}.ics`
    a.click()
    URL.revokeObjectURL(url)

    this.popoverTarget.classList.add("hidden")
  }

  openGoogle() {
    const dt = new Date(this.datetimeTarget.value)
    if (isNaN(dt)) return
    const end = new Date(dt.getTime() + 30 * 60000)
    const title = encodeURIComponent(`Reminder: review idea ${this.titleValue}`)
    const details = encodeURIComponent(`${this.urlValue}\n\nScore: ${this.scoreValue}\nState: ${this.stateValue}\n\n${this.snippetValue}`)
    const dates = `${this._formatDateUTC(dt)}/${this._formatDateUTC(end)}`

    const url = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${title}&dates=${dates}&details=${details}`
    window.open(url, "_blank")

    this.popoverTarget.classList.add("hidden")
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target) && document.activeElement !== this.datetimeTarget) {
      this.popoverTarget.classList.add("hidden")
    }
  }

  _escapeIcsText(str) {
    if (!str) return ''
    return str
      .replace(/\\/g, '\\\\')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,')
      .replace(/\r?\n/g, '\\n')
  }

  _foldIcsLine(line) {
    const maxLen = 75
    if (line.length <= maxLen) return line
    let result = line.slice(0, maxLen)
    let pos = maxLen
    while (pos < line.length) {
      result += '\r\n ' + line.slice(pos, pos + maxLen - 1)
      pos += maxLen - 1
    }
    return result
  }

  _formatDateUTC(date) {
    const y = date.getUTCFullYear()
    const m = String(date.getUTCMonth() + 1).padStart(2, "0")
    const d = String(date.getUTCDate()).padStart(2, "0")
    const h = String(date.getUTCHours()).padStart(2, "0")
    const min = String(date.getUTCMinutes()).padStart(2, "0")
    const s = String(date.getUTCSeconds()).padStart(2, "0")
    return `${y}${m}${d}T${h}${min}${s}Z`
  }
}
