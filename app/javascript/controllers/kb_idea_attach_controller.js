import { Controller } from "@hotwired/stimulus"

// "Attach to idea…": inline idea search, then POSTs the KB image to the idea's
// attachments (optionally as hero). Opened for the viewed image, or for another
// file via a kb-video-shot:attach event (screenshot toast).
export default class extends Controller {
  static targets = ["panel", "input", "results", "status", "hero", "name"]
  static values = { url: String, searchUrl: String, src: Number, file: String, name: String }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  open(event) {
    const detail = event?.detail || {}
    this.target = { file: detail.file || this.fileValue, name: detail.name || this.nameValue }
    this.opener = document.activeElement
    this.nameTarget.textContent = this.target.name
    this.panelTarget.hidden = false
    this.statusTarget.textContent = "Type to find the idea."
    this.resultsTarget.replaceChildren()
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  close() {
    this.panelTarget.hidden = true
    this.opener?.focus?.()
  }

  search() {
    window.clearTimeout(this.timer)
    const q = this.inputTarget.value.trim()
    if (!q) return this.resultsTarget.replaceChildren()
    this.timer = window.setTimeout(() => this.fetchIdeas(q), 200)
  }

  async fetchIdeas(q) {
    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", q)
      const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok || this.inputTarget.value.trim() !== q) return
      const { results } = await response.json()
      this.renderResults(results, q)
    } catch {
      this.statusTarget.textContent = "Search failed."
    }
  }

  renderResults(results, q) {
    if (!results.length) {
      const empty = document.createElement("li")
      empty.className = "kb-idea-attach__empty"
      empty.textContent = `No ideas match “${q}”.`
      return this.resultsTarget.replaceChildren(empty)
    }
    this.resultsTarget.replaceChildren(...results.map((idea) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = idea.title
      button.addEventListener("click", () => this.attach(idea, button))
      item.append(button)
      return item
    }))
  }

  async attach(idea, button) {
    if (this.busy) return
    this.busy = true
    button.disabled = true
    this.statusTarget.textContent = "Attaching…"
    try {
      const body = new URLSearchParams({
        src: this.srcValue, file: this.target.file, idea_id: idea.id, hero: this.heroTarget.checked ? "1" : ""
      })
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        credentials: "same-origin",
        body
      })
      const result = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(result.error || "Could not attach.")
      this.done(result)
    } catch (error) {
      this.statusTarget.textContent = error.message
      button.disabled = false
    } finally {
      this.busy = false
    }
  }

  done(result) {
    const link = document.createElement("a")
    link.href = result.idea.url
    link.textContent = result.idea.title
    this.statusTarget.replaceChildren(
      document.createTextNode(result.hero ? "Attached and set as hero on " : "Attached to "), link)
    this.resultsTarget.replaceChildren()
    this.dispatch("done", { detail: result })
  }
}
