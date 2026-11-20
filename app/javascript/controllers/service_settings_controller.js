import { Controller } from "@hotwired/stimulus"

// Settings > Services: probe each service with the (unsaved) field values, light the lamp.
export default class extends Controller {
  static targets = ["row", "input", "testAllButton"]
  static values = { testUrl: String }

  touched(e) {
    const row = e.target.closest(".svc-row")
    row.querySelector(".svc-reset").hidden = e.target.value.trim() === ""
    this.setState(row, "unknown", "not tested")
  }

  reset(e) {
    const row = e.target.closest(".svc-row")
    const input = e.target.closest(".svc-input-row").querySelector("input")
    input.value = ""
    input.placeholder = input.dataset.effective || input.placeholder
    e.target.hidden = true
    this.setState(row, "unknown", "not tested")
    input.focus()
  }

  test(e) { return this.probe(e.target.closest(".svc-row")) }

  async testAll() {
    this.testAllButtonTarget.disabled = true
    await Promise.all(this.rowTargets.map((r) => this.probe(r)))
    this.testAllButtonTarget.disabled = false
  }

  async probe(row) {
    this.setState(row, "testing", "testing…")
    const overrides = {}
    row.querySelectorAll("input[data-env]").forEach((i) => {
      if (i.value.trim() !== "") overrides[i.dataset.env] = i.value.trim()
    })
    try {
      const res = await fetch(this.testUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? ""
        },
        body: JSON.stringify({ key: row.dataset.key, overrides })
      })
      const d = await res.json()
      const ms = d.ms != null ? ` · ${Math.round(d.ms)}ms` : ""
      const state = ["ok", "error", "off"].includes(d.status) ? d.status : d.ok ? "ok" : "error"
      const text = state === "ok" ? `ok${ms}` : state === "off" ? "off" : `${d.detail || "error"}${ms}`
      this.setState(row, state, text)
    } catch (err) {
      this.setState(row, "error", "request failed")
    }
  }

  setState(row, state, text) {
    row.dataset.state = state
    row.querySelector('[data-role="result"]').textContent = text
  }

  async copy(e) {
    const btn = e.target
    const text = btn.closest(".svc-code").querySelector("code").textContent
    try {
      await navigator.clipboard.writeText(text)
      btn.textContent = "Copied"
    } catch (err) {
      btn.textContent = "Select + copy"
    }
    setTimeout(() => (btn.textContent = "Copy"), 1500)
  }
}
