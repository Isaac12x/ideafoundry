import { Controller } from "@hotwired/stimulus"
import { topSearches, recordSearch, clearSearches } from "lib/search_history"
import { binding, matches, isMac } from "lib/shortcut_bindings"
import * as ps from "lib/palette_state"

export default class extends Controller {
  static values = { searchUrl: String }
  static targets = ["input", "results", "key", "crumb", "mode", "status"]
  static modes = ["quick", "similar", "deep"]
  static placeholders = { quick: "Search or jump to...  (> for commands)", similar: "Similar to a typed phrase, or pick Find similar on a result", deep: "Search inside ideas, notes and KB files" }

  connect() {
    this._timer = null
    this._selectedIndex = -1
    this._seed = null // { label, params } from "Find similar"
    this._state = ps.initialState()
    this._terms = []
    this._boundKeydown = this._globalKeydown.bind(this)
    this._boundOpen = () => this.open()
    document.addEventListener("keydown", this._boundKeydown)
    document.addEventListener("command-palette:open", this._boundOpen)
    this.keyTargets.forEach((el) => { el.textContent = binding("search") })
  }

  get _level() { return this._state.level }
  get _saved() { return this._state.saved }
  get _mode() { return this._state.mode }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown)
    document.removeEventListener("command-palette:open", this._boundOpen)
    clearTimeout(this._timer)
  }

  _globalKeydown(e) {
    // Cmd+P (Mac) / Ctrl+P: the palette instead of the print dialog, even inside inputs.
    const mod = isMac() ? e.metaKey && !e.ctrlKey : e.ctrlKey && !e.metaKey
    if ((mod && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "p") || matches(binding("search"), e)) {
      e.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.element.open) return

    this.element.showModal()
    this.inputTarget.focus()
    this.inputTarget.select()
    this._state = { ...this._state, level: 0, saved: null }
    this._paint()
    this.search()
  }

  close() {
    this.element.close()
  }

  onCancel(e) {
    if (this._level === 1) { e.preventDefault(); this._back(); return }
    this._reset()
  }

  backdropClick(e) {
    if (e.target === this.element) this.close()
  }

  search() {
    clearTimeout(this._timer)
    this._abort?.abort()
    const raw = this.inputTarget.value
    const q = raw.trim()
    if (this._level === 1) { this._renderActions(q); return }
    const { commandsOnly, text } = ps.parseQuery(q)
    if (commandsOnly) { this._render(this._actions(text, true)); return }
    if (!q && !this._seed) { this._showHint(); return }
    if (this._mode === "quick") this._render(this._actions(q))
    if (!this._seed && q.length < ps.minChars(this._mode)) return // short queries match everything; deep/similar hit the disk
    this._timer = setTimeout(() => this._fetch(q), ps.DEBOUNCE_MS)
  }

  navigate(e) {
    const input = this.inputTarget
    if (e.altKey && /^Digit[123]$/.test(e.code)) { e.preventDefault(); this.setMode(this.constructor.modes[+e.code.slice(5) - 1]); return }
    if (e.key === "Backspace" && !input.value) {
      if (this._level === 1) { e.preventDefault(); this._back() } else if (this._seed) { e.preventDefault(); this.clearSeed() }
      return
    }
    if (e.key === "ArrowLeft" && this._level === 1 && input.selectionStart === 0) { e.preventDefault(); this._back(); return }
    if (e.key === "Escape" && this._level === 1) { e.preventDefault(); this._back(); return }

    const items = this.resultsTarget.querySelectorAll(".cp-result")
    if ((e.key === "ArrowRight" && input.selectionStart === input.value.length) || (e.key === "Tab" && !e.shiftKey)) {
      // Tab only drills in when there is something to drill into; otherwise it moves focus normally (the dialog traps it).
      if (ps.canEnter(this._state, this._flat[this._selectedIndex])) { e.preventDefault(); this._enter(this._flat[this._selectedIndex]) }
      return
    }
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp" && e.key !== "Enter") return
    if (!items.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._selectedIndex = Math.min(this._selectedIndex + 1, items.length - 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const item = this._flat[this._selectedIndex >= 0 ? this._selectedIndex : 0]
      if (item) this._activate(item)
      return
    }

    this._highlight()
  }

  // One place for the visual highlight and what assistive tech hears.
  _highlight() {
    const rows = this.resultsTarget.querySelectorAll(".cp-result")
    rows.forEach((el, i) => {
      const on = i === this._selectedIndex
      el.classList.toggle("cp-result--active", on)
      el.setAttribute("aria-selected", String(on))
    })
    const cur = rows[this._selectedIndex]
    if (cur) this.inputTarget.setAttribute("aria-activedescendant", cur.id)
    else this.inputTarget.removeAttribute("aria-activedescendant")
    this.inputTarget.setAttribute("aria-expanded", String(rows.length > 0))
    cur?.scrollIntoView({ block: "nearest" })
  }

  setModeFromChip(e) { this.setMode(e.currentTarget.dataset.mode) }

  setMode(mode) {
    this._state = ps.setMode(this._state, mode)
    if (this._mode !== "similar") this._seed = null
    this._paint()
    this.inputTarget.focus()
    this.search()
  }

  clearSeed() {
    this._seed = null
    this._paint()
    this.search()
  }

  // Drill in: the highlighted item's action list. Remember the query and row so Left/Backspace restores them.
  _enter(item) {
    this._state = ps.enter(this._state, { query: this.inputTarget.value, index: this._selectedIndex, groups: this._groups, item })
    this.inputTarget.value = ""
    this._paint()
    this._renderActions("")
  }

  _back() {
    const prev = ps.back(this._state)
    if (!prev) return
    const { query, index, groups } = prev
    this._state = prev.state
    this.inputTarget.value = query
    this._paint()
    this._render(groups, index)
    this.inputTarget.focus()
  }

  _renderActions(q) {
    const item = this._saved.item
    const list = ps.actionRows(item, q)
    this._render(list.length ? [{ label: `Actions for ${item.title}`, items: list }] : [])
  }

  _paint() {
    const item = this._saved?.item
    const chips = []
    if (this._level === 1) chips.push(`${item.kind || "item"}: ${item.title}`)
    else if (this._seed) chips.push(`similar to: ${this._seed.label}`)
    this.crumbTarget.hidden = !chips.length
    this.crumbTarget.textContent = chips.join("")
    this.modeTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.mode === this._mode)))
    this.inputTarget.placeholder = this._level === 1 ? "Filter actions" : this.constructor.placeholders[this._mode]
    this._status("")
  }

  _status(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    clearTimeout(this._statusTimer)
    if (text) this._statusTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 2500)
  }

  _activate(item) {
    if (item.query) return this._runQuery(item.query)
    if (item.cmd) return this._command(item.cmd)
    switch (item.run) {
      case "tab": this.close(); window.open(item.url, "_blank", "noopener"); return
      case "copy": return this._copy(item.value)
      case "post": return this._post(item)
      case "similar": return this._similar(item)
      default: this._go(item.url)
    }
  }

  async _copy(value) {
    const text = String(value).startsWith("/") ? window.location.origin + value : value
    try { await navigator.clipboard.writeText(text); this._status("Copied") } catch { this._status("Copy failed") }
  }

  async _post(item) {
    try {
      const resp = await fetch(item.url, {
        method: "POST", credentials: "same-origin",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: new URLSearchParams(item.params || {})
      })
      if (!resp.ok) throw new Error(resp.status)
      this.close()
      if (item.refresh !== false) window.Turbo?.visit(window.location.href, { action: "replace" })
    } catch { this._status("Could not do that") }
  }

  _similar(item) {
    const { run, label, url, ...params } = item
    this._seed = { label: this._saved?.item.title, params }
    this._state = ps.setMode(this._state, "similar")
    this.inputTarget.value = ""
    this._paint()
    this.inputTarget.focus()
    this._fetch("")
  }

  _command(cmd) {
    this.close()
    const body = document.body
    const ctl = (id) => this.application.getControllerForElementAndIdentifier(body, id)
    // After the dialog is gone: the shortcuts and the lock ignore keys/clicks while a modal is open.
    setTimeout(() => {
      if (cmd === "lock") ctl("typing-activity") ? ctl("typing-activity").manualLock() : this._visit(body.dataset.shortcutsSettingsUrlValue)
      else if (cmd === "haze") ctl("shortcuts")?.togglePrivacy()
      else if (cmd === "agent") document.querySelector("[data-shortcut-role~='ask-agent'], .ask-agent-launcher")?.click()
    })
  }

  _store() { try { return window.localStorage } catch { return null } }

  _go(url) {
    const store = this._store()
    if (store) recordSearch(store, this.inputTarget.value)
    this.close()
    this._visit(url)
  }

  _runQuery(q) {
    this.inputTarget.value = q
    this.search()
    this.inputTarget.focus()
  }

  clearHistory() {
    const store = this._store()
    if (store) clearSearches(store)
    this._showHint()
  }

  _history() {
    const store = this._store()
    const queries = store ? topSearches(store) : []
    this._histQ = queries
    if (!queries.length) return null
    const wrap = document.createElement("div")
    const head = document.createElement("div")
    head.className = "cp-group cp-group--history"
    head.innerHTML = `<span>Recent searches</span><button type="button" class="cp-clear">Clear</button>`
    head.lastChild.addEventListener("click", () => this.clearHistory())
    wrap.append(head)
    queries.forEach((q, n) => {
      const a = document.createElement("a")
      a.className = "cp-result"
      a.id = `cp_hist_${n}`
      a.setAttribute("role", "option")
      a.href = "#"
      a.dataset.query = q
      a.innerHTML = `<div class="cp-result-main"><span class="cp-result-title"></span></div>`
      a.querySelector(".cp-result-title").textContent = q
      a.addEventListener("click", (e) => { e.preventDefault(); this._runQuery(q) })
      wrap.append(a)
    })
    return wrap
  }

  async _fetch(q) {
    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", q)
      url.searchParams.set("mode", this._mode)
      Object.entries(this._seed?.params || {}).forEach(([k, v]) => url.searchParams.set(k, v))
      this._abort?.abort() // cancel the stale request
      this._abort = new AbortController()
      const resp = await fetch(url, { headers: { Accept: "application/json" }, signal: this._abort.signal })
      if (!resp.ok) throw new Error(resp.status)
      const { groups, terms } = await resp.json()
      if (!this.hasInputTarget || this._level === 1 || this.inputTarget.value.trim() !== q) return // stale response
      const list = groups || []
      this._terms = terms || []
      if (this._mode !== "quick") { this._render(list); return }
      // No idea matched: offer to start one titled with the query (full visit; `new` makes a draft and redirects).
      const newUrl = document.body.dataset.shortcutsNewIdeaUrlValue
      const create = newUrl && !list.some((g) => g.label === "Ideas")
        ? [{ label: "Actions", items: [{ title: `Create idea “${q}”`, hint: "action", url: `${newUrl}?title=${encodeURIComponent(q)}` }] }] : []
      this._render([...list, ...this._actions(q), ...create]) // real matches first: Enter must not start an idea when a project/folder matched
    } catch { /* silently fail */ }
  }

  // Navigation and "new" actions reuse the URLs the layout already puts on <body> for the keyboard shortcuts.
  _actions(q = "", commandsOnly = false) {
    const d = document.body.dataset
    const all = [
      ["Ideas", "Ideas"], ["Plan", "Plan"], ["Intake", "Intake"], ["Topologies", "Topologies"], ["Licensing", "Licensing"],
      ["Knowledge Base", "Kb"], ["Backlog", "Backlog"], ["Settings", "Settings"],
      ["New idea", "NewIdea"], ["New named list", "NewList"], ["New topology", "NewTopology"], ["Import submissions", "Import"]
    ]
    const nav = all.map(([title, key]) => ({ title, hint: title.startsWith("New") || title.startsWith("Import") ? "action" : "go to", url: d[`shortcuts${key}UrlValue`] }))
    const cmds = [{ title: "Lock now", hint: "command", cmd: "lock" }, { title: "Toggle privacy haze", hint: "command", cmd: "haze" }, { title: "Ask agent", hint: "command", cmd: "agent" }]
    const items = [...(commandsOnly ? [] : nav), ...cmds].filter((i) => (i.url || i.cmd) && i.title.toLowerCase().includes(q.toLowerCase()))
    return items.length ? [{ label: "Actions", items }] : []
  }

  _render(groups, active = 0) {
    this._groups = groups
    this._flat = groups.flatMap((g) => g.items)
    this._selectedIndex = -1

    if (!groups.length) {
      this.resultsTarget.innerHTML = this._level === 1 ? `<p class="cp-empty">No such action</p>`
        : `<p class="cp-empty">No results${this.inputTarget.value.trim() ? ` for <b>${this._esc(this.inputTarget.value.trim())}</b>` : ""}${this._mode === "quick" ? "<span>Try Deep to search inside notes and files</span>" : ""}</p>`
      this._highlight()
      return
    }

    const frag = document.createDocumentFragment()
    let i = 0
    groups.forEach((group) => {
      const h = document.createElement("p")
      h.className = "cp-group"
      h.setAttribute("role", "presentation")
      h.textContent = group.label
      frag.appendChild(h)
      group.items.forEach((item) => {
        const a = document.createElement("a")
        a.className = "cp-result"
        a.href = item.url || "#"
        a.dataset.url = item.url || ""
        const idx = i++
        a.id = `cp_opt_${idx}`
        a.setAttribute("role", "option")
        a.innerHTML = `
          <div class="cp-result-main">
            <span class="cp-result-title">${this._hl(item.title)}</span>
            ${item.hint ? `<span class="cp-result-state">${this._esc(item.hint)}</span>` : ""}
            ${item.actions && this._level === 0 ? `<span class="cp-more" aria-hidden="true">›</span>` : ""}
          </div>
          ${item.snippet ? `<div class="cp-result-snippet">${this._hl(item.snippet)}</div>` : ""}`
        a.addEventListener("click", (e) => {
          e.preventDefault()
          if (e.target.closest(".cp-more")) { this._selectedIndex = idx; this._enter(item) } else this._activate(item)
        })
        frag.appendChild(a)
      })
    })

    this.resultsTarget.replaceChildren(frag)
    const rows = this.resultsTarget.querySelectorAll(".cp-result")
    this._selectedIndex = Math.min(active, rows.length - 1)
    this._highlight()
  }

  // Escaped text with the Deep-search words wrapped in <mark>.
  _hl(text) {
    const safe = this._esc(text)
    const terms = this._terms.filter((t) => t.length > 1).map((t) => this._esc(t).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    return terms.length ? safe.replace(new RegExp(`(${terms.join("|")})`, "gi"), "<mark>$1</mark>") : safe
  }

  _showHint() {
    this._render(this._actions())
    const history = this._history()
    if (!history) return
    this._flat = [...this._histQ.map((q) => ({ query: q })), ...this._flat]
    this.resultsTarget.prepend(history)
    this._selectedIndex = 0
    this._highlight()
  }

  _reset() {
    this.inputTarget.value = ""
    this._state = { ...this._state, level: 0, saved: null }
    this._seed = null
    this._terms = []
    this._paint()
    this._showHint()
  }

  _visit(url) {
    if (typeof Turbo !== "undefined") {
      Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
