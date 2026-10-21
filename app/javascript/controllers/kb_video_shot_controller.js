import { Controller } from "@hotwired/stimulus"

// Captures the current video frame server-side (exact timestamp, full
// resolution, no CORS limits) into a PNG in a folder named like the video. Press
// S in the player or use the button; the toast offers Open and Copy, the strip
// under the player lists the frames (click = seek, Open = view the image).
export default class extends Controller {
  static targets = ["video", "toast", "strip", "shotTemplate"]
  static values = { url: String, src: Number, file: String, private: Boolean }

  connect() {
    for (const control of this.element.querySelectorAll(".kb-shot button, .kb-shot a")) control.tabIndex = -1
    this.rove(this.element.querySelector(".kb-shot"))
  }

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
    this.addShot(result)
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

  addShot({ name, time, url, serve_url }) {
    const item = this.shotTemplateTarget.content.firstElementChild.cloneNode(true)
    const tenths = Math.round(time * 10)
    const stamp = `${Math.floor(tenths / 600)}:${String(Math.floor((tenths % 600) / 10)).padStart(2, "0")}${tenths % 10 ? `.${tenths % 10}` : ""}`
    item.dataset.time = time.toFixed(1)
    item.classList.add("kb-shot--new")
    const img = item.querySelector("img")
    img.src = serve_url
    img.alt = `Frame at ${stamp}`
    item.querySelector(".kb-shot__time").textContent = stamp
    item.querySelector(".kb-shot__seek").title = `Jump to ${stamp}`
    const open = item.querySelector(".kb-shot__open")
    open.href = url
    open.title = `Open ${name}`
    open.setAttribute("aria-label", `Open frame at ${stamp}`)
    for (const control of item.querySelectorAll("button, a")) control.tabIndex = -1
    const list = this.stripTarget.querySelector(".kb-shots__list")
    // oldest first; ties keep capture order
    const next = [...list.children].find((li) => Number(li.dataset.time) > time)
    list.insertBefore(item, next || null)
    if (!this._rover) this.rove(item)
    this.reveal(item)
    this.track()
  }

  seek(event) {
    if (!this.hasVideoTarget) return
    const li = event.currentTarget.closest("li")
    this.videoTarget.currentTime = Number(li.dataset.time)
    this.rove(li)
    if (event.detail) this.videoTarget.focus({ preventScroll: true }) // keyboard Enter (detail 0) keeps focus in the strip
  }

  // Roving tabindex: one tab stop (seek + its Open link) for the whole strip.
  rove(li) {
    if (!li || li === this._rover) return
    for (const el of [this._rover, li]) {
      if (!el) continue
      const on = el === li
      for (const control of el.querySelectorAll("button, a")) control.tabIndex = on ? 0 : -1
    }
    this._rover = li
  }

  // User is browsing the strip: leave its scroll position alone for a while.
  touched() {
    this._touched = Date.now()
  }

  stripKey(event) {
    const items = [...this.stripTarget.querySelectorAll(".kb-shot")]
    const from = items.indexOf(event.target.closest(".kb-shot"))
    const to = { ArrowLeft: from - 1, ArrowRight: from + 1, Home: 0, End: items.length - 1 }[event.key]
    if (from < 0 || to === undefined || event.altKey || event.ctrlKey || event.metaKey) return
    event.preventDefault()
    const target = items[Math.max(0, Math.min(items.length - 1, to))]
    this.touched()
    this.rove(target)
    target.querySelector(".kb-shot__seek").focus({ preventScroll: true })
    this.reveal(target)
  }

  // Scroll the strip (never the page) so `li` is centered, if it is not fully in view.
  reveal(li) {
    const list = this.stripTarget.querySelector(".kb-shots__list")
    const a = li.getBoundingClientRect()
    const b = list.getBoundingClientRect()
    if (a.left >= b.left && a.right <= b.right) return
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    list.scrollTo({ left: list.scrollLeft + a.left - b.left - (b.width - a.width) / 2, behavior })
  }

  // Mark the frame nearest the playhead (within 1.5s); touch only the old and new element.
  track() {
    if (!this.hasVideoTarget) return
    const now = this.videoTarget.currentTime
    let best, gap = 1.5
    for (const li of this.stripTarget.querySelectorAll(".kb-shot")) {
      const d = Math.abs(Number(li.dataset.time) - now)
      if (d <= gap) { best = li; gap = d }
    }
    if (best === this._cur) return
    this._cur?.querySelector(".kb-shot__seek").removeAttribute("aria-current")
    best?.querySelector(".kb-shot__seek").setAttribute("aria-current", "true")
    this._cur = best
    if (best && !this.videoTarget.paused && !(Date.now() - (this._touched || 0) < 3000)) this.reveal(best)
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
