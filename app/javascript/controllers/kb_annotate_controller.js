import { Controller } from "@hotwired/stimulus"
import { describe, locate, rootText, unwrap, wrap } from "lib/kb_anchor"

// Highlight / underline text in a KB document and keep it. Works on three
// surfaces, each a "root" whose text the marks are anchored to:
//   markdown  - the rendered article
//   embed     - the body of the docx/pptx/xlsx/html iframe (same-origin,
//               still script-free: sandbox="allow-same-origin")
//   pdf       - each page's pdf.js text layer, announced by kb-pdf as it renders
// Selecting text pops a marker toolbar; clicking a mark lets you recolour,
// restyle or erase it. Marks are saved per user + file (KbAnnotation).
const TOOL_KEY = "kb-annotate-tool"

const MARK_CSS = `
mark.kb-mark {
  color: inherit; padding: 0; border-radius: 0.18em 0.08em;
  background: linear-gradient(var(--kb-ink), var(--kb-ink)) no-repeat 0 var(--kb-y) / 100% var(--kb-h);
  -webkit-box-decoration-break: clone; box-decoration-break: clone;
  cursor: pointer; --kb-h: 100%; --kb-y: 0;
}
mark.kb-mark[data-style="underline"] { --kb-ink: var(--kb-pen) !important; --kb-h: 0.13em; --kb-y: 96%; border-radius: 0; }
mark.kb-mark[data-color="yellow"] { --kb-ink: oklch(0.93 0.16 98 / 0.62); --kb-pen: oklch(0.72 0.16 80); }
mark.kb-mark[data-color="green"]  { --kb-ink: oklch(0.9 0.13 150 / 0.5);  --kb-pen: oklch(0.6 0.15 150); }
mark.kb-mark[data-color="pink"]   { --kb-ink: oklch(0.86 0.12 0 / 0.5);    --kb-pen: oklch(0.6 0.19 10); }
mark.kb-mark[data-color="blue"]   { --kb-ink: oklch(0.87 0.09 235 / 0.55); --kb-pen: oklch(0.56 0.15 250); }
mark.kb-mark.is-active { outline: 1.5px solid var(--kb-pen); outline-offset: 1px; }
mark.kb-mark.is-fresh { animation: kb-mark-sweep 0.42s cubic-bezier(0.25, 1, 0.5, 1) both; }
@keyframes kb-mark-sweep { from { background-size: 0% var(--kb-h); } }
@media (prefers-reduced-motion: reduce) { mark.kb-mark.is-fresh { animation: none; } }
`

export default class extends Controller {
  static targets = ["toolbar", "tool", "swatch", "erase"]
  static values = { url: String, src: Number, file: String }

  connect() {
    this.roots = []
    this.marks = []
    this.tool = readTool()
    this.cleanups = []
    this.syncToolbar()

    this.listen(document, "pointerdown", (event) => this.dismissIfOutside(event))
    this.listen(document, "keydown", (event) => event.key === "Escape" && this.hide())
    this.listen(this.element.closest(".kb-content-area") || window, "scroll", () => this.hide(), true)

    const article = this.element.querySelector(".kb-markdown")
    if (article) this.addRoot(article, null)

    const frame = this.element.querySelector("iframe.kb-embed")
    if (frame) this.watchFrame(frame)

    this.load()
  }

  disconnect() {
    this.cleanups.forEach((fn) => fn())
    this.cleanups = []
  }

  // kb-pdf:page-text
  addPdfPage({ detail: { page, root } }) {
    this.addRoot(root, page)
  }

  // pointerup / keyup inside the document (markdown + pdf; the iframe wires its own)
  select(event) {
    this.handleSelection(document, event)
  }

  // Pressing a toolbar button must not collapse the text selection under it.
  keepSelection(event) {
    event.preventDefault()
  }

  setTool({ params: { style } }) {
    this.tool = style
    try { localStorage.setItem(TOOL_KEY, style) } catch {}
    if (this.editing) this.restyle(this.editing, { style })
    this.syncToolbar()
  }

  paint({ params: { color } }) {
    if (this.editing) return this.restyle(this.editing, { color })
    if (!this.pending) return

    const { root, doc, anchor, page } = this.pending
    const mark = { ...anchor, page, style: this.tool, color }
    this.apply(mark, root, doc, { fresh: true })
    this.marks.push(mark)
    doc.getSelection()?.removeAllRanges()
    this.hide()

    this.request("POST", this.collectionUrl(), { annotation: { ...anchor, page, style: mark.style, color } })
      .then((saved) => { mark.id = saved.id; mark.elements.forEach((el) => { el.dataset.id = saved.id }) })
      .catch(() => this.forget(mark))
  }

  erase() {
    const mark = this.editing
    if (!mark) return
    this.forget(mark)
    this.hide()
    if (mark.id) this.request("DELETE", `${this.urlValue}/${mark.id}`).catch(() => {})
  }

  // ── surfaces ────────────────────────────────────────────────────────────

  watchFrame(frame) {
    const ready = () => {
      const doc = frame.contentDocument
      if (!doc?.body) return
      const style = doc.createElement("style")
      style.textContent = MARK_CSS
      doc.head.appendChild(style)
      this.listen(doc, "pointerup", (event) => this.handleSelection(doc, event))
      this.listen(doc, "keyup", (event) => this.handleSelection(doc, event))
      this.listen(doc, "pointerdown", (event) => this.dismissIfOutside(event))
      this.listen(doc.defaultView, "scroll", () => this.hide())
      this.addRoot(doc.body, null, frame)
    }
    if (frame.contentDocument?.readyState === "complete" && frame.contentDocument.body?.childElementCount) ready()
    else this.listen(frame, "load", ready)
  }

  addRoot(element, page, frame = null) {
    const root = { element, page, frame, doc: element.ownerDocument }
    if (root.doc === document) injectCss(document)
    this.roots.push(root)
    if (this.loaded) this.marks.filter((mark) => onRoot(mark, root)).forEach((mark) => this.apply(mark, root.element, root.doc))
  }

  async load() {
    try {
      this.marks = await this.request("GET", this.collectionUrl())
    } catch {
      this.marks = []
    }
    this.loaded = true
    for (const root of this.roots) {
      this.marks.filter((mark) => onRoot(mark, root)).forEach((mark) => this.apply(mark, root.element, root.doc))
    }
  }

  apply(mark, rootElement, doc, { fresh = false } = {}) {
    const spot = locate(rootText(rootElement), mark)
    if (!spot) return
    mark.elements = wrap(rootElement, spot.start, spot.end, () => {
      const el = doc.createElement("mark")
      el.className = fresh ? "kb-mark is-fresh" : "kb-mark"
      el.dataset.style = mark.style
      el.dataset.color = mark.color
      if (mark.id) el.dataset.id = mark.id
      return el
    })
    if (fresh) mark.elements.forEach((el, i) => { el.style.animationDelay = `${Math.min(i, 8) * 45}ms` })
  }

  forget(mark) {
    unwrap(mark.elements || [])
    this.marks = this.marks.filter((other) => other !== mark)
  }

  restyle(mark, changes) {
    Object.assign(mark, changes)
    mark.elements?.forEach((el) => { el.dataset.style = mark.style; el.dataset.color = mark.color })
    this.syncToolbar()
    if (mark.id) {
      this.request("PATCH", `${this.urlValue}/${mark.id}`, { annotation: { style: mark.style, color: mark.color } }).catch(() => {})
    }
  }

  // ── selection + toolbar ─────────────────────────────────────────────────

  handleSelection(doc, event) {
    if (this.toolbarTarget.contains(event.target)) return
    const selection = doc.getSelection()
    const range = selection?.rangeCount ? selection.getRangeAt(0) : null

    if (!range || range.collapsed) {
      const hit = event.type === "pointerup" && event.target.closest?.("mark.kb-mark")
      const mark = hit && this.marks.find((candidate) => candidate.elements?.includes(hit))
      return mark ? this.showFor(mark, hit, doc) : this.hide()
    }

    const root = this.roots.find((candidate) => candidate.doc === doc &&
      candidate.element.contains(range.startContainer) && candidate.element.contains(range.endContainer))
    const anchor = root && describe(root.element, range)
    if (!anchor) return this.hide()

    this.pending = { root: root.element, doc, page: root.page, anchor }
    this.editing = null
    this.show(range.getBoundingClientRect(), root.frame)
  }

  showFor(mark, element, doc) {
    this.pending = null
    this.editing = mark
    const root = this.roots.find((candidate) => candidate.doc === doc && candidate.element.contains(element))
    this.show(element.getBoundingClientRect(), root?.frame)
  }

  show(rect, frame) {
    this.clearActive()
    this.editing?.elements?.forEach((el) => el.classList.add("is-active"))
    this.syncToolbar()

    const offset = frame ? frame.getBoundingClientRect() : { top: 0, left: 0 }
    const bar = this.toolbarTarget
    bar.hidden = false
    const width = bar.offsetWidth
    const height = bar.offsetHeight
    const centre = offset.left + rect.left + rect.width / 2
    let top = offset.top + rect.top - height - 10
    const below = top < 8
    if (below) top = offset.top + rect.bottom + 10
    bar.style.left = `${Math.min(Math.max(8, centre - width / 2), window.innerWidth - width - 8)}px`
    bar.style.top = `${top}px`
    bar.classList.toggle("is-below", below)
  }

  hide() {
    if (!this.hasToolbarTarget || this.toolbarTarget.hidden) return
    this.toolbarTarget.hidden = true
    this.clearActive()
    this.pending = null
    this.editing = null
  }

  dismissIfOutside(event) {
    if (!this.toolbarTarget.contains(event.target) && !event.target.closest?.("mark.kb-mark")) this.hide()
  }

  clearActive() {
    this.marks.forEach((mark) => mark.elements?.forEach((el) => el.classList.remove("is-active")))
  }

  syncToolbar() {
    const current = this.editing
    const style = current?.style || this.tool
    this.toolTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.kbAnnotateStyleParam === style))
    this.swatchTargets.forEach((button) =>
      button.setAttribute("aria-pressed", Boolean(current) && button.dataset.kbAnnotateColorParam === current.color))
    this.toolbarTarget.dataset.style = style
    this.eraseTarget.hidden = !current
  }

  // ── plumbing ────────────────────────────────────────────────────────────

  collectionUrl() {
    const params = new URLSearchParams({ src: this.srcValue, file: this.fileValue })
    return `${this.urlValue}?${params}`
  }

  async request(method, url, body) {
    const response = await fetch(url, {
      method,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? ""
      },
      body: body && JSON.stringify(body)
    })
    if (!response.ok) throw new Error(`annotation ${method} failed: ${response.status}`)
    return response.status === 204 ? null : response.json()
  }

  listen(target, type, handler, capture = false) {
    target.addEventListener(type, handler, capture)
    this.cleanups.push(() => target.removeEventListener(type, handler, capture))
  }
}

function onRoot(mark, root) {
  return (mark.page ?? null) === root.page
}

function readTool() {
  try { return localStorage.getItem(TOOL_KEY) === "underline" ? "underline" : "highlight" } catch { return "highlight" }
}

function injectCss(doc) {
  if (doc.getElementById("kb-mark-css")) return
  const style = doc.createElement("style")
  style.id = "kb-mark-css"
  style.textContent = MARK_CSS
  doc.head.appendChild(style)
}
