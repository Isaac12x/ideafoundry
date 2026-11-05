import { Controller } from "@hotwired/stimulus"

// In-app ebook reader. EPUBs open directly (epub.js, paginated, content iframes sandboxed without
// allow-scripts); other formats are converted server-side to a sidecar EPUB (Calibre) or PDF (DjVu)
// first -- this controller polls that state and offers "Convert to read".
//
// Public surface for a bookmarks/TOC panel:
//   events (bubble from the element):  kb-book:toc      detail: TOC array [{ id, href, label, subitems }]
//                                      kb-book:location detail: { cfi, href, chapter, percentage }
//   methods:  goTo(target)  target = CFI | href | 0..1 progress   (also via a "kb-book:goto" event, detail = target)
//   getters:  location, toc
export default class extends Controller {
  static targets = ["stage", "notice", "message", "convert", "bar", "location"]
  static values = { url: String, statusUrl: String, bundleUrl: String, key: String }

  connect() {
    this.gone = false
    this.toc = []
    this.location = null
    this._storeKey = `kb-resume:book:${this.keyValue}`
    this._onGoto = (event) => this.goTo(event.detail)
    this.element.addEventListener("kb-book:goto", this._onGoto)
    // Page keys only when focus is in the reader or nowhere (the tree uses arrows too).
    this._onKey = (event) => { if (this.element.contains(event.target) || event.target === document.body) this._flip(event) }
    window.addEventListener("keydown", this._onKey)
    if (this.urlValue) this.open(this.urlValue)
    else this.poll()
  }

  disconnect() {
    this.gone = true
    clearTimeout(this._timer)
    this.element.removeEventListener("kb-book:goto", this._onGoto)
    window.removeEventListener("keydown", this._onKey)
    this._resizer?.disconnect()
    this._book?.destroy()
    this._book = this._rendition = null
  }

  previous() { this._rendition?.prev() }

  next() { this._rendition?.next() }

  goTo(target) {
    if (!this._rendition || target == null) return
    if (typeof target === "number") {
      const cfi = this._book.locations.length() ? this._book.locations.cfiFromPercentage(Math.min(Math.max(target, 0), 1)) : null
      return cfi && this._rendition.display(cfi)
    }
    return this._rendition.display(target)
  }

  async open(url) {
    this.say("Opening book…")
    try {
      const [{ ePub }, response] = await Promise.all([import(this.bundleUrlValue), fetch(url, { credentials: "same-origin" })])
      if (!response.ok) throw new Error("download failed")
      const buffer = await response.arrayBuffer()
      if (this.gone) return
      this.noticeTarget.hidden = true
      this.stageTarget.hidden = false
      this.barTarget.hidden = false
      this._book = ePub(buffer)
      this._rendition = this._book.renderTo(this.stageTarget, { width: "100%", height: "100%", flow: "paginated", spread: "auto", allowScriptedContent: false })
      this._theme()
      this._rendition.on("relocated", (location) => this._relocated(location))
      this._rendition.on("keyup", (event) => this._flip(event))
      await this._rendition.display(localStorage.getItem(this._storeKey) || undefined)
      if (this.gone) return
      // Observe only once the view manager exists. ResizeObserver fires once on observe(); a resize clears
      // epub.js's views, so ignore unchanged sizes and re-display the current spot after a real one.
      let size = `${this.stageTarget.clientWidth}x${this.stageTarget.clientHeight}`
      this._resizer = new ResizeObserver(() => {
        const { clientWidth: w, clientHeight: h } = this.stageTarget
        if (!this._rendition?.manager || !w || !h || size === `${w}x${h}`) return
        size = `${w}x${h}`
        const cfi = this._rendition.currentLocation()?.start?.cfi
        this._rendition.resize(w, h)
        this._rendition.display(cfi || undefined).catch(() => {})
      })
      this._resizer.observe(this.stageTarget)
      this._book.loaded.navigation.then((navigation) => {
        this.toc = navigation.toc
        this.dispatch("toc", { detail: this.toc })
      })
      this._book.ready.then(() => this._book.locations.generate(1600)).then(() => this._relocated(this._rendition.currentLocation())).catch(() => {})
    } catch {
      this.noticeTarget.hidden = false
      this.stageTarget.hidden = true
      this.barTarget.hidden = true
      this.say("This book could not be opened. You can still download it.")
    }
  }

  async poll() {
    if (this.gone) return
    try {
      const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      this.show(await response.json())
    } catch {
      this.say("Could not check conversion status.")
    }
  }

  show(state) {
    this.convertTarget.hidden = true
    if (state.status === "ready") return state.format === "pdf" ? this.openPdf(state.url) : this.open(state.url)
    if (state.status === "running") {
      this.say("Converting to a readable format. This can take a minute…")
      this._timer = setTimeout(() => this.poll(), 2000)
    } else if (state.status === "missing_tool") {
      this.say(state.hint)
    } else if (state.status === "failed") {
      this.say(`Conversion failed: ${state.error}`)
      this.convertTarget.hidden = false
    } else {
      this.say("This format has to be converted before it can be read here.")
      this.convertTarget.hidden = false
    }
  }

  async convert() {
    this.convertTarget.hidden = true
    this.say("Starting conversion…")
    try {
      const response = await fetch(this.statusUrlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        credentials: "same-origin"
      })
      const state = await response.json()
      if (!response.ok && state.error) {
        this.say(state.error)
        return state.status === "missing_tool" ? null : (this.convertTarget.hidden = false)
      }
      this.show(state)
    } catch {
      this.say("Could not start the conversion.")
      this.convertTarget.hidden = false
    }
  }

  // DjVu is converted to PDF: hand it to the regular PDF viewer.
  openPdf(url) {
    this.noticeTarget.hidden = true
    this.barTarget.hidden = true
    this.stageTarget.hidden = false
    const viewer = document.createElement("div")
    viewer.className = "kb-pdf-viewer"
    viewer.dataset.controller = "kb-pdf"
    viewer.dataset.kbPdfUrlValue = url
    viewer.dataset.kbPdfKeyValue = this.keyValue
    this.stageTarget.replaceChildren(viewer)
    this.stageTarget.classList.add("kb-book__stage--pdf")
  }

  say(text) { this.messageTarget.textContent = text }

  _relocated(location) {
    const start = location?.start
    if (!start) return
    const chapter = this._chapter(start.href)
    const percentage = this._book.locations.length() ? this._book.locations.percentageFromCfi(start.cfi) : null
    this.location = { cfi: start.cfi, href: start.href, chapter, percentage }
    localStorage.setItem(this._storeKey, start.cfi)
    this.locationTarget.textContent = [chapter, percentage == null ? null : `${Math.round(percentage * 100)}%`].filter(Boolean).join(" · ")
    this.dispatch("location", { detail: this.location })
  }

  _chapter(href) {
    const flat = (items) => items.flatMap((item) => [item, ...flat(item.subitems || [])])
    const file = (value) => String(value).split("#")[0]
    return flat(this.toc).find((item) => file(item.href) === file(href))?.label?.trim()
  }

  _theme() {
    const style = getComputedStyle(this.element)
    this._rendition.themes.default({ img: { "max-width": "100%" } })
    this._rendition.themes.override("color", style.color)
    this._rendition.themes.override("font-family", style.fontFamily)
    this._rendition.themes.override("background", "transparent")
  }

  _flip(event) {
    if (!this._rendition || event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target?.closest?.("input, textarea, select, [contenteditable]")) return
    if (event.key === "ArrowRight") { event.preventDefault?.(); this.next() }
    else if (event.key === "ArrowLeft") { event.preventDefault?.(); this.previous() }
  }
}
