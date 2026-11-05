import { Controller } from "@hotwired/stimulus"

// Right-hand "Bookmarks" panel for paged documents (pdf, comic, epub, converted books).
// "Contents" is the document's own outline; "Your bookmarks" are saved server-side per file.
// It only talks to the viewer through events, so it works for any of them:
//   in  (bubble up from the viewer): kb-pdf:outline / kb-pdf:page, kb-book:toc / kb-book:location, kb-comic:page
//   out (sent to the viewer):        kb-pdf:goto / kb-comic:goto (detail = page), kb-book:goto (detail = CFI or href)
const OPEN_KEY = "kb-bookmarks-open"
const NARROW = "(max-width: 900px)"
const typing = (el) => !!el?.closest?.("input, textarea, select, [contenteditable]")
const fileOf = (href) => String(href || "").split("#")[0]
const order = (a, b) => (a.page ?? 0) - (b.page ?? 0) || (a.progress ?? 0) - (b.progress ?? 0) || a.id - b.id

export default class extends Controller {
  static targets = ["panel", "toggle", "contents", "outline", "list", "empty", "status", "add"]
  static values = { url: String, src: String, file: String }

  connect() {
    this.items = []
    this.marks = []
    this.current = {}
    this._narrow = window.matchMedia(NARROW)
    this._setOpen(this._narrow.matches ? false : this._stored() !== "0")
    this._onKey = (event) => {
      if (event.key.toLowerCase() !== "b" || event.metaKey || event.ctrlKey || event.altKey || event.defaultPrevented || typing(event.target)) return
      event.preventDefault()
      this.add()
    }
    window.addEventListener("keydown", this._onKey)
    this._load()
  }

  disconnect() {
    window.removeEventListener("keydown", this._onKey)
    clearTimeout(this._undoTimer)
  }

  // ── viewer events ───────────────────────────────────────────────────────

  outline(event) {
    this.items = event.detail.map((item) => ({ label: item.label, page: item.page, depth: item.depth }))
    this._renderOutline()
  }

  toc(event) {
    const flat = (nodes, depth) => nodes.flatMap((n) => [{ label: n.label?.trim() || "Untitled", href: n.href, depth }, ...flat(n.subitems || [], depth + 1)])
    this.items = flat(event.detail || [], 0)
    this._renderOutline()
  }

  page(event) {
    this.current = { page: event.detail.page }
    this._highlight()
  }

  location(event) {
    this.current = { ...event.detail }
    this._highlight()
  }

  // ── panel ───────────────────────────────────────────────────────────────

  toggle() {
    this._setOpen(this.panelTarget.hidden)
    if (!this.panelTarget.hidden) this.addTarget.focus()
  }

  close() {
    if (this.panelTarget.hidden) return
    this._setOpen(false)
    this.toggleTarget.focus()
  }

  click(event) {
    const el = event.target.closest("[data-act]")
    if (!el) return
    const { act, index, id } = el.dataset
    if (act === "outline") this._go(this.items[index])
    else if (act === "mark") this._go(this.marks.find((m) => m.id === +id))
    else if (act === "rename") this._edit(+id)
    else if (act === "delete") this._remove(+id)
    else if (act === "undo") this._undelete()
  }

  async add() {
    const where = this._here()
    if (!where) return
    try {
      const mark = await this._request("POST", this._collection(), { bookmark: where })
      this.marks = [...this.marks, mark].sort(order)
      this._renderMarks()
      this._say(`Bookmarked “${mark.label}”.`)
      if (this.panelTarget.hidden) this._setOpen(true)
      this._edit(mark.id)
    } catch (error) {
      this._say(error.message)
    }
  }

  // ── bookmarks ───────────────────────────────────────────────────────────

  _here() {
    const c = this.current
    if (c.cfi) {
      const pct = c.percentage == null ? null : `${Math.round(c.percentage * 100)}%`
      return { cfi: c.cfi, progress: c.percentage ?? null, label: [c.chapter, pct].filter(Boolean).join(" · ") || "Bookmark" }
    }
    const entry = this.items[this._activeIndex()]
    return c.page ? { page: c.page, label: entry?.label || `Page ${c.page}` } : null
  }

  async _load() {
    try {
      this.marks = await this._request("GET", this._collection())
    } catch {
      this._say("Could not load bookmarks.")
    }
    this._renderMarks()
  }

  _edit(id) {
    const row = this.listTarget.querySelector(`[data-mark-id="${id}"]`)
    const mark = this.marks.find((m) => m.id === id)
    const go = row?.querySelector(".kb-bookmarks__go")
    if (!go) return
    const input = Object.assign(document.createElement("input"), { type: "text", value: mark.label, maxLength: 120, className: "kb-bookmarks__input" })
    input.setAttribute("aria-label", "Bookmark name")
    let done = false
    const finish = async (save) => {
      if (done) return
      done = true
      const label = input.value.trim()
      if (save && label && label !== mark.label) {
        try { Object.assign(mark, await this._request("PATCH", this._member(id), { bookmark: { label } })) } catch (error) { this._say(error.message) }
      }
      this._renderMarks()
      this.listTarget.querySelector(`[data-mark-id="${id}"] .kb-bookmarks__go`)?.focus()
    }
    input.addEventListener("keydown", (event) => {
      event.stopPropagation()
      if (event.key === "Enter") { event.preventDefault(); finish(true) } else if (event.key === "Escape") finish(false)
    })
    input.addEventListener("blur", () => finish(true))
    go.replaceWith(input)
    input.focus()
    input.select()
  }

  async _remove(id) {
    const mark = this.marks.find((m) => m.id === id)
    try {
      await this._request("DELETE", this._member(id))
    } catch (error) {
      return this._say(error.message)
    }
    this.marks = this.marks.filter((m) => m.id !== id)
    // Inline 5s undo: the row is already gone server-side, so undo re-creates it.
    clearTimeout(this._undoTimer)
    this._undo = mark
    this._undoTimer = setTimeout(() => { this._undo = null; this._renderMarks() }, 5000)
    this._renderMarks()
    this._say(`Deleted “${mark?.label}”.`)
    this.addTarget.focus()
  }

  async _undelete() {
    const { label, page, cfi, progress } = this._undo
    clearTimeout(this._undoTimer)
    this._undo = null
    try {
      const mark = await this._request("POST", this._collection(), { bookmark: { label, page, cfi, progress } })
      this.marks = [...this.marks, mark].sort(order)
      this._say(`Restored “${mark.label}”.`)
    } catch (error) {
      this._say(error.message)
    }
    this._renderMarks()
  }

  _go(target) {
    if (!target) return
    const find = (name) => this.element.querySelector(`[data-controller~="${name}"]`)
    let viewer, name, detail
    if (target.page) {
      viewer = find("kb-pdf") || find("kb-comic")
      name = viewer?.dataset.controller.includes("kb-pdf") ? "kb-pdf:goto" : "kb-comic:goto"
      detail = target.page
    } else {
      viewer = find("kb-book")
      name = "kb-book:goto"
      detail = target.cfi || target.href
    }
    viewer?.dispatchEvent(new CustomEvent(name, { detail }))
    if (this._narrow.matches) this.close()
  }

  // ── rendering ───────────────────────────────────────────────────────────

  _renderOutline() {
    this.contentsTarget.hidden = this.items.length === 0
    this.outlineTarget.replaceChildren(...this.items.map((item, index) => {
      const button = this._button(item.label, "kb-bookmarks__go", { act: "outline", index })
      button.style.paddingLeft = `${0.5 + Math.min(item.depth, 5) * 0.75}rem`
      if (item.page) button.append(this._meta(`p. ${item.page}`))
      return this._li(button)
    }))
    this._highlight()
  }

  _renderMarks() {
    this.emptyTarget.hidden = this.marks.length > 0
    this.listTarget.replaceChildren(...this.marks.map((mark) => {
      const go = this._button(mark.label, "kb-bookmarks__go", { act: "mark", id: mark.id })
      if (mark.page) go.append(this._meta(`p. ${mark.page}`))
      else if (mark.progress != null) go.append(this._meta(`${Math.round(mark.progress * 100)}%`))
      const rename = this._button("✎", "kb-bookmarks__tool", { act: "rename", id: mark.id }, `Rename ${mark.label}`)
      const del = this._button("×", "kb-bookmarks__tool", { act: "delete", id: mark.id }, `Delete ${mark.label}`)
      const li = this._li(go, rename, del)
      li.dataset.markId = mark.id
      return li
    }))
    if (this._undo) {
      const undo = this._button("Undo", "btn btn-sm", { act: "undo" }, "Undo delete")
      const note = Object.assign(document.createElement("span"), { className: "kb-bookmarks__label", textContent: `Deleted “${this._undo.label}”` })
      this.listTarget.append(this._li(note, undo))
    }
    this._highlight()
  }

  // aria-current on the outline entry the reader is inside and on any bookmark sitting here.
  _activeIndex() {
    const c = this.current
    let active = -1
    this.items.forEach((item, i) => {
      const hit = item.page ? c.page && item.page <= c.page && (active < 0 || item.page >= this.items[active].page) : c.href && fileOf(item.href) === fileOf(c.href)
      if (hit) active = i
    })
    return active
  }

  _highlight() {
    const c = this.current
    const active = this._activeIndex()
    this.outlineTarget.querySelectorAll("[data-act]").forEach((el, i) => this._current(el, i === active))
    this.listTarget.querySelectorAll("[data-act='mark']").forEach((el) => {
      const mark = this.marks.find((m) => m.id === +el.dataset.id)
      this._current(el, !!mark && (mark.page ? mark.page === c.page : mark.cfi === c.cfi))
    })
    this.addTarget.disabled = !(c.page || c.cfi)
  }

  _current(el, on) {
    if (on) el.setAttribute("aria-current", "location")
    else el.removeAttribute("aria-current")
  }

  _li(...children) {
    const li = document.createElement("li")
    li.className = "kb-bookmarks__item"
    li.append(...children)
    return li
  }

  _button(text, className, data, label) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = className
    Object.assign(button.dataset, data)
    if (label) { button.setAttribute("aria-label", label); button.title = label }
    const span = document.createElement("span")
    span.className = "kb-bookmarks__label"
    span.textContent = text
    if (label) button.textContent = text
    else button.append(span)
    return button
  }

  _meta(text) {
    const span = document.createElement("span")
    span.className = "kb-bookmarks__page"
    span.textContent = text
    return span
  }

  _say(text) { this.statusTarget.textContent = text }

  // ── plumbing ────────────────────────────────────────────────────────────

  _setOpen(open) {
    this.panelTarget.hidden = !open
    this.toggleTarget.setAttribute("aria-expanded", String(open))
    this.element.classList.toggle("is-open", open)
    if (!this._narrow.matches) {
      try { localStorage.setItem(OPEN_KEY, open ? "1" : "0") } catch { /* private mode */ }
    }
  }

  _stored() {
    try { return localStorage.getItem(OPEN_KEY) } catch { return null }
  }

  _collection() {
    return `${this.urlValue}?${new URLSearchParams({ src: this.srcValue, file: this.fileValue })}`
  }

  _member(id) { return `${this.urlValue}/${id}` }

  async _request(method, url, body) {
    const response = await fetch(url, {
      method,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? ""
      },
      credentials: "same-origin",
      body: body && JSON.stringify(body)
    })
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}))
      throw new Error(detail.error || `Bookmark request failed (${response.status})`)
    }
    return response.status === 204 ? null : response.json()
  }
}
