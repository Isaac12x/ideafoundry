import { Controller } from "@hotwired/stimulus"

// Related control in the file header. Ways to link: drag from the handle onto a tree row (line follows the
// pointer, snaps to rows), Down arrow on the handle (same line, rows picked with the arrows), or the search popover.
// Hovering the handle or a chip draws lines to the related rows. Overlay is one fixed SVG on <body>.
const NS = "http://www.w3.org/2000/svg"
const ROW = ".kb-file-row, .kb-dir-header"
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches
const key = (src, rel) => `${src}:${rel}`
const SEEN = "kb-related-hint-seen"
const GRACE = 700 // ms after the drawer opens in which pointercancel / lostpointercapture are noise
const curve = (a, b) => {
  const dx = Math.max(48, Math.abs(a.x - b.x) / 2)
  return `M${a.x} ${a.y}C${a.x - dx} ${a.y} ${b.x + dx} ${b.y} ${b.x} ${b.y}`
}
const node = (tag, cls, parent) => {
  const n = document.createElementNS(NS, tag)
  n.setAttribute("class", cls)
  parent.append(n)
  return n
}
let overlay, justLinked, hopFrom // justLinked: "src:path" -> chip that animates in after the swap; hopFrom: file we left via a chip

const layer = () => {
  if (!overlay?.isConnected) {
    overlay = document.createElementNS(NS, "svg")
    overlay.setAttribute("class", "kb-related-lines")
    overlay.setAttribute("aria-hidden", "true")
    document.body.append(overlay)
  }
  return overlay
}

const scroller = () => {
  let n = document.getElementById("kb-sidebar-tree")
  for (let p = n; p; p = p.parentElement) if (/auto|scroll/.test(getComputedStyle(p).overflowY)) return p
  return n
}

const rowAt = (x, y) => { // elementsFromPoint, not elementFromPoint: the drawer scrim must not hide rows
  for (const el of document.elementsFromPoint(x, y)) {
    const row = el.closest(ROW)
    if (row?.closest("#kb-sidebar-tree")) return row
  }
  return null
}

// "src:rel" -> row, built once per peek and again only when the tree mutates.
const treeRows = () => {
  const m = new Map()
  document.getElementById("kb-sidebar-tree")?.querySelectorAll(ROW).forEach((r) => {
    const k = key(r.dataset.kbTreeSrcParam, r.dataset.kbTreeRelParam)
    if (!m.has(k)) m.set(k, r)
  })
  return m
}

// Right edge of a tree row; null when hidden. Scrolled out of the tree's viewport s: pinned to its top/bottom edge (edge = arrow).
const anchor = (row, s) => {
  const r = row.getBoundingClientRect()
  if (!r.height) return null
  const x = r.right - 8
  const y = r.top + r.height / 2
  if (!s || (y >= s.top && y <= s.bottom)) return { x, y }
  return { x, y: Math.min(s.bottom - 8, Math.max(s.top + 8, y)), edge: y < s.top ? "\u2191" : "\u2193" }
}

// Row to draw a chip's line to: its own, else the nearest visible ancestor folder (via).
const target = (chip, rows, s) => {
  const parts = chip.dataset.peerPath.split("/")
  for (let i = parts.length; i > 0; i--) {
    const row = rows.get(key(chip.dataset.peerSrc, parts.slice(0, i).join("/")))
    const a = row && anchor(row, s)
    if (a) return { row, a, via: i < parts.length }
  }
}

export default class extends Controller {
  static targets = ["details", "form", "input", "results", "peerSrc", "peerPath", "handle", "chip", "hint", "live"]
  static values = { searchUrl: String, src: Number, rel: String }

  connect() {
    const fresh = this.chipTargets.find((c) => key(c.dataset.peerSrc, c.dataset.peerPath) === justLinked)
    if (fresh) {
      fresh.classList.add("is-new")
      this._say(`Linked to ${fresh.dataset.peerPath}`)
    }
    justLinked = null
    this._mode()
    try {
      if (!localStorage.getItem(SEEN)) { this.element.classList.add("is-hinted"); localStorage.setItem(SEEN, "1") }
    } catch { /* ponytail: storage off -> hint stays hover-only */ }
    // Chain hop: briefly line back to the file we just came from.
    const from = this.chipTargets.find((c) => key(c.dataset.peerSrc, c.dataset.peerPath) === hopFrom)
    hopFrom = null
    if (from) this._hopFrame = requestAnimationFrame(() => {
      this._peekOn(from)
      this._hopTimer = setTimeout(() => this._cancelPeek(), 1600)
    })
  }

  disconnect() {
    cancelAnimationFrame(this._hopFrame)
    this._cancelPeek()
    this._down = null
    if (this._drag) this._end(false)
  }

  // Dragging needs a tree: "tree" (visible), "drawer" (off-canvas, the Files button opens it) or none (search only).
  _mode() {
    const toggle = document.querySelector(".kb-drawer-toggle")
    const tree = document.getElementById("kb-sidebar-tree")
    const mode = toggle?.offsetParent ? "drawer" : tree?.checkVisibility?.({ visibilityProperty: true }) ? "tree" : null
    this.handleTarget.title = mode ? "Drag onto a file to relate" : "Search to relate"
    this.hintTarget.textContent = mode ? "Drag onto a file in the tree to relate it, or press Down arrow to pick one with the keyboard. Enter searches." : "Press Enter to search for an entry to relate."
    return mode
  }

  hop(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    hopFrom = key(this.srcValue, this.relValue)
    setTimeout(() => { hopFrom = null }, 3000)
  }

  // ---- search popover ----
  opened() {
    if (this.detailsTarget.open) this.inputTarget.focus()
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetch(this.inputTarget.value.trim()), 200)
  }

  async _fetch(query) {
    if (!query) return this._render([])
    try {
      const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" } })
      this._render((await response.json()).results || [])
    } catch {
      this._render([])
    }
  }

  _render(results) {
    const list = this.resultsTarget
    list.replaceChildren(...results.filter((r) => r.type !== "project" && !this._isSelf(r.src, r.path)).map((entry) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.setAttribute("role", "option")
      button.textContent = `${entry.path}${entry.type === "dir" ? "/" : ""}`
      button.title = entry.source
      button.addEventListener("click", () => this.pick(entry))
      item.append(button)
      return item
    }))
    list.hidden = !list.children.length
  }

  pick(entry) {
    justLinked = key(entry.src, entry.path)
    this.peerSrcTarget.value = entry.src
    this.peerPathTarget.value = entry.path
    this.formTarget.requestSubmit()
  }

  _isSelf(src, rel) { return Number(src) === this.srcValue && rel === this.relValue }
  _isPeer(src, rel) { return this.chipTargets.some((c) => Number(c.dataset.peerSrc) === Number(src) && c.dataset.peerPath === rel) }

  _start() {
    const r = this.handleTarget.getBoundingClientRect()
    return { x: r.left + 9, y: r.top + r.height / 2 }
  }

  // ---- hover: lines to related rows ----
  peek(event) {
    if (this._drag) return
    this._mode()
    this._peekOn(event.currentTarget.classList.contains("kb-related__item") ? event.currentTarget : null)
  }

  unpeek(event) {
    // moving handle -> chip keeps the lines; only leave when focus/pointer is outside every control
    const to = event.relatedTarget
    if (event.type === "blur" && this._drag?.kb) return this._end(false) // focus left the handle: link mode is over
    if (to && this.element.contains(to) && to.closest(".kb-related__item, .kb-related__trigger")) return
    this._cancelPeek()
  }

  _peekOn(focus) {
    this._focus = focus
    if (!this._peek) {
      const tree = document.getElementById("kb-sidebar-tree")
      const kick = () => { // reposition at most once a frame, only on scroll / resize / tree changes
        if (!this._peekFrame) this._peekFrame = requestAnimationFrame(() => { this._peekFrame = 0; this._place() })
      }
      const mo = new MutationObserver(() => { if (this._peek) this._peek.rows = null; kick() })
      if (tree) mo.observe(tree, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] })
      addEventListener("scroll", kick, { capture: true, passive: true })
      addEventListener("resize", kick)
      this._peek = { g: node("g", "kb-rl__peek", layer()), paths: new Map(), hinted: new Set(), rows: null, mo, kick }
    }
    this._place()
  }

  _place() {
    const pk = this._peek
    if (!pk) return
    pk.rows ||= treeRows()
    const from = this._start()
    const s = scroller()?.getBoundingClientRect()
    const hits = this.chipTargets.map((chip) => [chip, target(chip, pk.rows, s)]).filter(([, t]) => t)
    const hidden = new Map() // row -> peers folded into it
    hits.forEach(([, t]) => { if (t.via) hidden.set(t.row, (hidden.get(t.row) || 0) + 1) })
    const seen = new Set()
    const hinted = new Set()
    hits.forEach(([chip, t]) => {
      seen.add(chip)
      let p = pk.paths.get(chip)
      if (!p) {
        p = node("path", "kb-rl__line", pk.g)
        p.setAttribute("pathLength", "1")
        p.dot = node("circle", "kb-rl__dot is-peek", pk.g)
        p.dot.setAttribute("r", "3.5")
        p.label = node("text", "kb-rl__label", pk.g)
        pk.paths.set(chip, p)
      }
      const strong = chip === this._focus
      const dim = !!this._focus && !strong
      p.setAttribute("d", curve(from, t.a))
      p.dot.setAttribute("cx", t.a.x)
      p.dot.setAttribute("cy", t.a.y)
      p.label.setAttribute("x", t.a.x - 9)
      p.label.setAttribute("y", t.a.y + 3.5)
      p.label.textContent = t.a.edge || (t.via ? `+${hidden.get(t.row)}` : "")
      p.classList.toggle("is-strong", strong)
      p.classList.toggle("is-dim", dim)
      p.dot.classList.toggle("is-dim", dim)
      p.dot.classList.toggle("is-via", t.via || !!t.a.edge)
      p.label.classList.toggle("is-dim", dim)
      if (!t.via && !t.a.edge) hinted.add(t.row)
    })
    pk.paths.forEach((p, chip) => { if (!seen.has(chip)) { p.dot.remove(); p.label.remove(); p.remove(); pk.paths.delete(chip) } })
    pk.hinted.forEach((row) => { if (!hinted.has(row)) row.classList.remove("is-related-hint") })
    hinted.forEach((row) => { if (!row.classList.contains("is-related-hint")) row.classList.add("is-related-hint") })
    pk.hinted = hinted
  }

  _cancelPeek() {
    clearTimeout(this._hopTimer)
    if (!this._peek) return
    const { g, hinted, mo, kick } = this._peek
    cancelAnimationFrame(this._peekFrame)
    this._peekFrame = 0
    mo.disconnect()
    removeEventListener("scroll", kick, { capture: true })
    removeEventListener("resize", kick)
    hinted.forEach((row) => row.classList.remove("is-related-hint"))
    this._peek = this._focus = null
    g.classList.add("is-out")
    setTimeout(() => g.remove(), 200)
  }

  // ---- drag a line from the handle onto a tree row (or Down arrow: same line, rows picked with the keys) ----
  down(event) {
    if (event.button !== 0 || this._drag || !this._mode()) return // no tree: the click just opens the search popover
    this._swallow = false
    this._down = { x: event.clientX, y: event.clientY, id: event.pointerId }
    this._ptr = { x: event.clientX, y: event.clientY }
    this.handleTarget.setPointerCapture(event.pointerId)
  }

  move(event) {
    if (!this._down) return
    this._ptr = { x: event.clientX, y: event.clientY }
    if (!this._drag && Math.hypot(event.clientX - this._down.x, event.clientY - this._down.y) > 4) this._begin()
  }

  up() {
    if (!this._down) return
    this._down = null
    if (this._drag) this._end(true)
  }

  // Element-level cancel only matters before the drag begins; after that the window listeners own the gesture.
  cancelPointer() {
    if (!this._drag) this._down = null
  }

  _cancelWin() {
    if (this._drag && performance.now() - (this._drag.opened || -GRACE) > GRACE) this._end(false) // drawer opening cancels capture: ignore
  }

  // Handle focused: Down arrow enters link mode (Enter / Space still open the search popover).
  key(event) {
    if (event.key !== "ArrowDown" || this._drag || !this._mode()) return
    event.preventDefault()
    if (this.detailsTarget.open) this.detailsTarget.open = false
    this._begin(true)
  }

  // A drag must not toggle the popover.
  guard(event) {
    if (this._swallow) { event.preventDefault(); this._swallow = false }
  }

  _begin(kb) {
    this._cancelPeek()
    if (this.detailsTarget.open) this.detailsTarget.open = false
    const start = this._start()
    const g = node("g", "kb-rl__drag", layer())
    const toggle = document.querySelector(".kb-drawer-toggle")
    const drawer = this._mode() === "drawer" && toggle.getAttribute("aria-expanded") === "false" ? toggle : null
    drawer?.click() // narrow screens: reveal the Files drawer for the drag
    this._drag = {
      g, state: "drag", start, pos: { ...start }, row: null, drawer, tree: scroller(), kb: !!kb, opened: drawer ? performance.now() : 0,
      line: node("path", "kb-rl__line is-live", g), dot: node("circle", "kb-rl__dot", g),
    }
    this._drag.dot.setAttribute("r", "4")
    this._swallow = !kb
    document.documentElement.classList.add("kb-linking")
    // Window-level: opening the drawer cancels the handle's pointer capture, which must not end the drag.
    this._onKey = (e) => this._keydown(e)
    this._onBlur = () => this._end(false)
    this._onMove = (e) => this.move(e)
    this._onUp = () => this.up()
    this._onCancel = () => this._cancelWin()
    document.addEventListener("keydown", this._onKey)
    addEventListener("blur", this._onBlur)
    addEventListener("pointermove", this._onMove)
    addEventListener("pointerup", this._onUp)
    addEventListener("pointercancel", this._onCancel)
    if (drawer && this._down) try { this.handleTarget.setPointerCapture(this._down.id) } catch { /* pointer already gone */ }
    if (kb) { this._ptr = { ...start }; this._go(0) }
    this._t = 0
    this._raf = requestAnimationFrame((t) => this._tick(t))
  }

  _keydown(e) {
    const d = this._drag
    if (e.key === "Escape") return this._end(false)
    if (!d?.kb || e.defaultPrevented) return
    if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); this._go(e.key === "ArrowDown" ? 1 : -1) }
    else if (e.key === "Enter") {
      e.preventDefault()
      if (d.row && !d.denied) this._end(true)
      else this._say(d.row ? "Already related" : "No row selected")
    }
  }

  // Link mode: move the target through the visible rows (self / already related show as denied) and announce it.
  _go(step) {
    const d = this._drag
    const rows = [...d.tree.querySelectorAll(ROW)].filter((r) => r.getBoundingClientRect().height)
    const row = rows[Math.min(rows.length - 1, Math.max(0, rows.indexOf(d.row) + (d.row ? step : 0)))]
    if (!row) return
    row.scrollIntoView({ block: "nearest" })
    this._setRow(row)
    const rel = row.dataset.kbTreeRelParam
    this._say(`Link to ${rel}${row.classList.contains("kb-dir-header") ? "/" : ""}?${d.denied ? " Not available, already related." : " Press Enter to link."}`)
  }

  _say(text) { this.liveTarget.textContent = text }

  _tick(t) {
    const d = this._drag
    if (!d) return
    const dt = Math.min(48, t - (this._t || t))
    this._t = t
    if (d.state === "drag" && !d.kb) this._hit(dt)
    const row = d.row
    const target = d.state === "retract" ? d.start : (row && anchor(row, d.tree.getBoundingClientRect())) || (d.kb ? d.start : this._ptr)
    const k = reduced() ? 1 : 1 - Math.exp(-dt / 50)
    d.pos.x += (target.x - d.pos.x) * k
    d.pos.y += (target.y - d.pos.y) * k
    if (this.hasHandleTarget) d.start = this._start() // controller is gone after the swap; keep the last start
    d.line.setAttribute("d", curve(d.start, d.pos))
    d.dot.setAttribute("cx", d.pos.x)
    d.dot.setAttribute("cy", d.pos.y)
    if (d.state !== "drag" && Math.hypot(target.x - d.pos.x, target.y - d.pos.y) < 1.5) return this._finish()
    this._raf = requestAnimationFrame((n) => this._tick(n))
  }

  // Row state (target / denied / snapped dot) and the folder dwell: a collapsed folder opens after 600ms, underline fills meanwhile.
  _setRow(row) {
    const d = this._drag
    if (row === d.row) return
    d.row?.classList.remove("is-link-target", "is-link-denied", "is-dwelling")
    d.row = row
    const src = row?.dataset.kbTreeSrcParam
    const rel = row?.dataset.kbTreeRelParam
    d.denied = !!row && (this._isSelf(src, rel) || this._isPeer(src, rel))
    row?.classList.add(d.denied ? "is-link-denied" : "is-link-target")
    d.dot.classList.toggle("is-snapped", !!row && !d.denied)
    d.dot.classList.toggle("is-denied", !!row && d.denied)
    clearTimeout(d.dwell)
    if (row?.classList.contains("kb-dir-header") && row.closest(".kb-dir-group")?.classList.contains("is-collapsed")) {
      row.classList.add("is-dwelling")
      d.dwell = setTimeout(() => { row.classList.remove("is-dwelling"); row.querySelector(".kb-dir-toggle")?.click() }, 600)
    }
  }

  // Pointer: which row is under it, and tree auto-scroll near the edges.
  _hit(dt) {
    const d = this._drag
    this._setRow(rowAt(this._ptr.x, this._ptr.y))
    const s = d.tree?.getBoundingClientRect()
    const edge = 40
    if (s && this._ptr.x >= s.left && this._ptr.x <= s.right) {
      const v = this._ptr.y < s.top + edge ? -(s.top + edge - this._ptr.y) : this._ptr.y > s.bottom - edge ? this._ptr.y - (s.bottom - edge) : 0
      if (v) d.tree.scrollTop += Math.max(-18, Math.min(18, v / 3)) * dt / 16
    }
  }

  _end(commit) {
    this._down = null // gesture over: moves are ignored until the next pointerdown
    const d = this._drag
    if (!d || d.state !== "drag") return
    clearTimeout(d.dwell)
    document.removeEventListener("keydown", this._onKey)
    removeEventListener("blur", this._onBlur)
    removeEventListener("pointermove", this._onMove)
    removeEventListener("pointerup", this._onUp)
    removeEventListener("pointercancel", this._onCancel)
    document.documentElement.classList.remove("kb-linking")
    const row = d.row
    row?.classList.remove("is-link-target", "is-link-denied", "is-dwelling")
    const closeDrawer = () => d.drawer?.getAttribute("aria-expanded") === "true" && d.drawer.click()
    if (commit && row && !d.denied) {
      d.state = "settle"
      d.committed = true
      const src = row.dataset.kbTreeSrcParam
      const rel = row.dataset.kbTreeRelParam
      d.dot.classList.add("is-done")
      row.classList.add("is-link-done")
      setTimeout(() => row.classList.remove("is-link-done"), 900)
      setTimeout(closeDrawer, 500) // let the line land before the drawer slides away
      justLinked = key(src, rel)
      this.peerSrcTarget.value = src
      this.peerPathTarget.value = rel
      this.formTarget.requestSubmit()
    } else {
      d.state = "retract"
      d.row = null
      this._say("Link cancelled")
      d.dot.classList.remove("is-snapped", "is-denied")
      closeDrawer()
    }
    if (!this._raf) this._raf = requestAnimationFrame((n) => this._tick(n))
  }

  _finish() {
    const d = this._drag
    this._drag = this._raf = null
    d.g.classList.add("is-out")
    setTimeout(() => d.g.remove(), d.committed ? 500 : 250)
  }
}
