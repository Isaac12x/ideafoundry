import { Controller } from "@hotwired/stimulus"
import { findMatches, stepIndex } from "lib/find_bar"

// Replaces the browser's Cmd/Ctrl+F with an in-app bar. Highlights via the CSS Custom Highlight API
// (<mark> wrapping if unsupported). Viewers with their own find (Excalidraw, PDF.js) keep it, and a
// second Cmd+F inside the bar falls through to the native one.
const SKIP = "script, style, noscript, textarea, input, select, nav, [hidden], [aria-hidden='true'], .find-bar"
const OWN_FIND = "[data-controller~='kb-pdf'], [data-controller~='excalidraw'], .excalidraw"

export default class extends Controller {
  static targets = ["bar", "input", "count", "case"]

  connect() {
    this.matches = []; this.current = -1; this.marks = []; this.ranges = []
    this.onKey = (e) => this.key(e)
    this.onLoad = () => this.close()
    document.addEventListener("keydown", this.onKey, true)
    document.addEventListener("turbo:load", this.onLoad)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey, true)
    document.removeEventListener("turbo:load", this.onLoad)
    this.clear()
  }

  key(event) {
    const find = (event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "f"
    if (find) {
      if (this.barTarget.contains(event.target)) return // second Cmd+F: native find
      if (event.target.closest?.(OWN_FIND) || document.querySelector("[data-controller~='excalidraw']")) return
      event.preventDefault()
      return this.open()
    }
    if (event.key === "Escape" && !this.barTarget.hidden && this.barTarget.contains(event.target)) this.close()
  }

  open() {
    if (this.barTarget.hidden) this.returnTo = document.activeElement
    const selected = window.getSelection()?.toString().trim()
    if (selected && !selected.includes("\n")) this.inputTarget.value = selected
    this.barTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
    this.run()
  }

  close() {
    if (this.barTarget.hidden) return
    this.clear()
    this.barTarget.hidden = true
    if (this.returnTo?.isConnected) this.returnTo.focus()
    this.returnTo = null
  }

  inputKey(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    this.step(event.shiftKey ? -1 : 1)
  }

  next() { this.step(1) }
  prev() { this.step(-1) }
  toggleCase() { this.run() }

  run() {
    this.clear()
    const nodes = this.textNodes()
    this.matches = findMatches(nodes.map((n) => n.data), this.inputTarget.value, this.caseTarget.checked)
      .map(({ node, start, end }) => ({ node: nodes[node], start, end }))
    if (!CSS.highlights) this.wrapAll()
    else this.ranges = this.matches.map((m) => this.range(m))
    this.current = this.matches.length ? 0 : -1
    this.paint()
  }

  step(dir) {
    if (!this.matches.length) return this.run()
    this.current = stepIndex(this.current, dir, this.matches.length)
    this.paint()
  }

  // Visible text of the main content (not nav/inputs/scripts); visibility checked once per parent.
  textNodes() {
    const root = document.getElementById("main-content") || document.body
    const seen = new Map()
    const ok = (el) => {
      if (!seen.has(el)) {
        seen.set(el, !el.closest(SKIP) && (el.checkVisibility ? el.checkVisibility({ checkVisibilityCSS: true }) : el.getClientRects().length > 0))
      }
      return seen.get(el)
    }
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.data.trim() && n.parentElement && ok(n.parentElement) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT)
    })
    const out = []
    while (walker.nextNode()) out.push(walker.currentNode)
    return out
  }

  range({ node, start, end }) {
    const r = new Range()
    r.setStart(node, start)
    r.setEnd(node, end)
    return r
  }

  wrapAll() {
    // Back to front so earlier offsets in the same node stay valid.
    this.marks = this.matches.map(() => null)
    for (let i = this.matches.length - 1; i >= 0; i--) {
      const { node, start, end } = this.matches[i]
      node.splitText(end)
      const mark = document.createElement("mark")
      mark.className = "find-mark"
      node.splitText(start).before(mark)
      mark.append(mark.nextSibling)
      this.marks[i] = mark
    }
  }

  paint() {
    const total = this.matches.length
    this.countTarget.textContent = !this.inputTarget.value ? "" : total ? `${this.current + 1} / ${total}` : "No results"
    if (!total) return CSS.highlights?.delete("find"), CSS.highlights?.delete("find-current")
    if (CSS.highlights) {
      CSS.highlights.set("find", new Highlight(...this.ranges))
      CSS.highlights.set("find-current", new Highlight(this.ranges[this.current]))
    } else {
      this.marks.forEach((m, i) => m.classList.toggle("find-mark--current", i === this.current))
    }
    const el = CSS.highlights ? this.ranges[this.current].startContainer.parentElement : this.marks[this.current]
    const calm = matchMedia("(prefers-reduced-motion: reduce)").matches
    el.scrollIntoView({ block: "center", behavior: calm ? "auto" : "smooth" })
  }

  clear() {
    CSS.highlights?.delete("find")
    CSS.highlights?.delete("find-current")
    const parents = new Set()
    this.marks.forEach((m) => {
      parents.add(m.parentNode)
      m.replaceWith(...m.childNodes)
    })
    parents.forEach((p) => p.normalize())
    this.marks = []
    this.matches = []
    this.ranges = []
    this.current = -1
  }
}
