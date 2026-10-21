import { Controller } from "@hotwired/stimulus"

// Captures the current video frame server-side (exact timestamp, full
// resolution, no CORS limits) into a PNG beside the video. Press S in the
// player or use the button; the toast offers Open and Copy.
export default class extends Controller {
  static targets = ["video", "toast"]
  static values = { url: String, src: Number, file: String, private: Boolean }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  key(event) {
    if (event.key.toLowerCase() !== "s" || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.closest("input, textarea, select, [contenteditable]")) return
    event.preventDefault()
    this.capture()
  }

  async capture() {
    if (this.busy || !this.hasVideoTarget) return
    this.busy = true
    const time = this.videoTarget.currentTime
    this.say("Capturing frame…")
    try {
      const body = new URLSearchParams({ src: this.srcValue, file: this.fileValue, time })
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body
      })
      const result = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(result.error || "Could not capture that frame.")
      this.done(result)
    } catch (error) {
      this.say(error.message)
    } finally {
      this.busy = false
    }
  }

  done(result) {
    const toast = this.toastTarget
    toast.replaceChildren()
    const label = document.createElement("span")
    label.textContent = `Saved ${result.name}`
    const open = document.createElement("a")
    open.href = result.url
    open.textContent = "Open"
    open.dataset.turboFrame = "kb-content"
    const copy = document.createElement("button")
    copy.type = "button"
    copy.textContent = "Copy"
    copy.addEventListener("click", () => this.copyImage(result, copy))
    const attach = document.createElement("button")
    attach.type = "button"
    attach.textContent = "Attach to idea…"
    attach.addEventListener("click", () => this.dispatch("attach", { detail: { file: result.file, name: result.name } }))
    toast.append(label, open, copy)
    if (!this.privateValue) toast.append(attach) // attaching 403s inside private projects
    this.show()
  }

  // kb-idea-attach:done -> confirm in the toast with a link to the idea.
  attached(event) {
    const { idea, hero } = event.detail
    const link = document.createElement("a")
    link.href = idea.url
    link.textContent = idea.title
    const label = document.createElement("span")
    label.textContent = hero ? "Attached, hero image set on" : "Attached to"
    this.toastTarget.replaceChildren(label, link)
    this.show()
  }

  async copyImage(result, button) {
    try {
      const blob = await (await fetch(result.serve_url)).blob()
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })])
      button.textContent = "Copied"
    } catch {
      button.textContent = "Copy failed"
    }
  }

  say(message) {
    this.toastTarget.textContent = message
    this.show()
  }

  show() {
    this.toastTarget.hidden = false
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => { this.toastTarget.hidden = true }, 8000)
  }
}
