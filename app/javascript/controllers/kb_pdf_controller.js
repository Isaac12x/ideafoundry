import { Controller } from "@hotwired/stimulus"

// Inline PDF viewer: continuous scroll, pages lazily rendered near the
// viewport, remembers the last-read page per file (localStorage,
// "kb-resume:<src>:<rel>") and reopens there. pdf.js is lazy-loaded from CDN
// only when a PDF is viewed. Each page gets pdf.js' invisible text layer on
// top of the canvas so text can be selected and copied. Each rendered text
// layer is announced as "kb-pdf:page-text" so kb-annotate can paint marks.
// Bookmarks panel hooks: emits "kb-pdf:outline" ([{ label, page, depth }]) and "kb-pdf:page"
// ({ page, pages }); accepts a "kb-pdf:goto" event (detail = page number) or goToPage(n).
// ponytail: no in-page search or zoom controls; add if they turn out to matter.
const PDFJS_VERSION = "4.10.38"
const PDFJS_URL = `https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.min.mjs`
const WORKER_URL = `https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSION}/build/pdf.worker.min.mjs`

let workerReady

async function loadPdfjs() {
  const pdfjs = await import(PDFJS_URL)
  // Same-origin blob so pdf.js can spawn a real worker; falls back to the
  // main-thread "fake worker" if the fetch fails.
  workerReady ??= fetch(WORKER_URL)
    .then((r) => r.blob())
    .then((blob) => URL.createObjectURL(blob))
    .catch(() => WORKER_URL)
  pdfjs.GlobalWorkerOptions.workerSrc = await workerReady
  return pdfjs
}

export default class extends Controller {
  static values = { url: String, key: String }

  async connect() {
    this._key = `kb-resume:${this.keyValue}`
    this._onGoto = (event) => this.goToPage(event.detail)
    this.element.addEventListener("kb-pdf:goto", this._onGoto)
    this.element.classList.add("is-loading")

    const pdfjs = await loadPdfjs()
    if (!this.element.isConnected) return
    this._pdfjs = pdfjs

    this._task = pdfjs.getDocument({ url: this.urlValue })
    try {
      this._pdf = await this._task.promise
    } catch (e) {
      this.element.classList.remove("is-loading")
      this.element.textContent = "Could not load PDF."
      return
    }
    if (!this.element.isConnected) return
    this.element.classList.remove("is-loading")

    await this._buildPages()
  }

  disconnect() {
    this.element.removeEventListener("kb-pdf:goto", this._onGoto)
    this._observer?.disconnect()
    this._resizeObserver?.disconnect()
    this._scroller?.removeEventListener("scroll", this._onScroll, true)
    clearTimeout(this._scrollTimer)
    this._task?.destroy()
  }

  async _buildPages() {
    // First page's aspect ratio sizes every placeholder; corrected per page
    // once rendered. Keeps startup at one getPage() even for huge PDFs.
    const first = await this._pdf.getPage(1)
    const vp = first.getViewport({ scale: 1 })

    this._holders = []
    this._layers = []
    for (let i = 1; i <= this._pdf.numPages; i++) {
      const holder = document.createElement("div")
      holder.className = "kb-pdf-page"
      holder.dataset.page = i
      holder.style.aspectRatio = `${vp.width} / ${vp.height}`
      this.element.appendChild(holder)
      this._holders.push(holder)
    }

    this._observer = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && this._renderHolder(e.target)),
      { root: this.element.closest("[data-pdf-scroller], .kb-content-area"), rootMargin: "100% 0px" }
    )
    this._holders.forEach((h) => this._observer.observe(h))

    // Text layers are positioned in absolute pixels, so they need re-laying
    // out whenever the page width changes.
    this._width = this.element.clientWidth
    this._resizeObserver = new ResizeObserver(() => this._onResize())
    this._resizeObserver.observe(this.element)

    const savedPage = parseInt(localStorage.getItem(this._key) || "1", 10)
    if (savedPage > 1 && this._holders[savedPage - 1]) {
      this._holders[savedPage - 1].scrollIntoView({ block: "start" })
    }
    this._trackCurrentPage()
    this._emitOutline()
  }

  goToPage(page) {
    const n = Math.min(Math.max(parseInt(page, 10) || 1, 1), this._holders?.length || 1)
    this._holders?.[n - 1]?.scrollIntoView({ block: "start" })
  }

  // The document's own outline, flattened with depth and resolved to page numbers.
  async _emitOutline() {
    let tree
    try { tree = await this._pdf.getOutline() } catch { return }
    const items = []
    const walk = async (nodes, depth) => {
      for (const node of nodes) {
        if (items.length >= 2000) return
        const page = await this._pageOf(node.dest)
        if (page) items.push({ label: node.title?.trim() || "Untitled", page, depth })
        if (node.items?.length) await walk(node.items, depth + 1)
      }
    }
    if (tree?.length) await walk(tree, 0)
    if (items.length && this.element.isConnected) this.dispatch("outline", { detail: items })
  }

  async _pageOf(dest) {
    try {
      const target = typeof dest === "string" ? await this._pdf.getDestination(dest) : dest
      if (!Array.isArray(target)) return null
      return Number.isInteger(target[0]) ? target[0] + 1 : (await this._pdf.getPageIndex(target[0])) + 1
    } catch {
      return null
    }
  }

  _renderHolder(holder) {
    this._observer.unobserve(holder)
    const pageNum = parseInt(holder.dataset.page, 10)
    this._pdf.getPage(pageNum).then(async (page) => {
      const scale = holder.clientWidth / page.getViewport({ scale: 1 }).width
      const viewport = page.getViewport({ scale })
      holder.style.aspectRatio = `${viewport.width} / ${viewport.height}`

      const textLayerDiv = document.createElement("div")
      textLayerDiv.className = "kb-pdf-text"
      textLayerDiv.style.setProperty("--scale-factor", scale)

      const ratio = window.devicePixelRatio || 1
      const canvas = document.createElement("canvas")
      canvas.width = Math.floor(viewport.width * ratio)
      canvas.height = Math.floor(viewport.height * ratio)
      holder.replaceChildren(canvas, textLayerDiv)

      const textLayer = new this._pdfjs.TextLayer({
        textContentSource: page.streamTextContent(),
        container: textLayerDiv,
        viewport
      })
      this._layers.push({ holder, page, div: textLayerDiv, textLayer })

      // Pixels and text in parallel: selection shouldn't wait on rasterising.
      await Promise.all([
        page.render({
          canvasContext: canvas.getContext("2d"),
          viewport,
          transform: ratio !== 1 ? [ratio, 0, 0, ratio, 0, 0] : null
        }).promise,
        textLayer.render().then(() => this.dispatch("page-text", { detail: { page: pageNum, root: textLayerDiv } }))
      ])
    }).catch(() => {})
  }

  _onResize() {
    const width = this.element.clientWidth
    if (!width || width === this._width) return
    this._width = width

    for (const layer of this._layers) {
      const scale = layer.holder.clientWidth / layer.page.getViewport({ scale: 1 }).width
      layer.div.style.setProperty("--scale-factor", scale)
      layer.textLayer.update({ viewport: layer.page.getViewport({ scale }) })
    }
  }

  // Nearest ancestor that really scrolls (the tracked scroller may only contain it).
  _scrollBox() {
    for (let el = this.element.parentElement; el && el !== document.body; el = el.parentElement) {
      if (/(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight) return el
    }
    return this._scroller
  }

  _trackCurrentPage() {
    // Standalone file page has no KB scroller: the document itself scrolls.
    this._scroller = this.element.closest("[data-pdf-scroller], .kb-content-area") || window

    const emit = () => {
      // First page whose bottom is below the actual scrolling box's top edge (notes/headers above don't count).
      const box = this._scroller === window ? null : this._scrollBox()
      const top = box ? box.getBoundingClientRect().top : 0
      const current = this._holders.find((h) => h.getBoundingClientRect().bottom > top + 40)
      if (!current) return
      localStorage.setItem(this._key, current.dataset.page)
      this.dispatch("page", { detail: { page: parseInt(current.dataset.page, 10), pages: this._holders.length } })
    }
    this._onScroll = () => {
      clearTimeout(this._scrollTimer)
      this._scrollTimer = setTimeout(emit, 300)
    }
    // Capture: the scrolling box may be a descendant of the observed scroller (scroll doesn't bubble).
    this._scroller.addEventListener("scroll", this._onScroll, true)
    emit()
  }
}
