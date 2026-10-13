import { Controller } from "@hotwired/stimulus"

const LS_KEY = "ptable:bench"

// Instrument modules: each exports mount<Name>(panel, ctx) → { update(ctx), focus?(opts), destroy() }.
const INSTRUMENTS = {
  combine: ["lib/periodic_table/bench_chem", "mountCombine"],
  formula: ["lib/periodic_table/bench_chem", "mountFormula"],
  equation: ["lib/periodic_table/bench_chem", "mountEquation"],
  alloy: ["lib/periodic_table/bench_chem", "mountAlloy"],
  compare: ["lib/periodic_table/bench_views", "mountCompare"],
  plot: ["lib/periodic_table/bench_views", "mountPlot"],
  nuclides: ["lib/periodic_table/bench_nuclides", "mountNuclides"],
  map: ["lib/periodic_table/bench_map", "mountMap"],
  guide: ["lib/periodic_table/bench_guide", "mountGuide"]
}

// Connects to data-controller="periodic-bench" (nested inside .ptable).
// The table owns the tray; this controller mirrors it and drives the
// instruments. All cross-talk is DOM events on the .ptable root.
export default class extends Controller {
  static targets = ["tray", "tab", "panel"]

  connect() {
    this.root = this.element.closest(".ptable")
    this.tray = []
    this.mounted = new Map()
    this.active = this._loadActive()

    this._on = {
      "periodic-table:ready": (e) => this._ready(e.detail.elements),
      "periodic-table:tray-change": (e) => this._trayChanged(e.detail.symbols),
      "periodic-bench:open": (e) => this._open(e.detail || {}),
      "periodic-table:highlight-cleared": () => this.mounted.forEach((m) => m.instance?.highlightCleared?.())
    }
    for (const [name, fn] of Object.entries(this._on)) this.root.addEventListener(name, fn)
    this._paintTabs()
    this._renderTray()
  }

  disconnect() {
    for (const [name, fn] of Object.entries(this._on)) this.root.removeEventListener(name, fn)
    this.mounted.forEach((m) => m.instance?.destroy?.())
    this.mounted.clear()
    this._disconnected = true
  }

  async _ready(elements) {
    if (this.ctxBase) return
    let chem, trends, compounds
    try {
      ;[chem, trends, compounds] = await Promise.all([
        import("lib/periodic_table/chem"),
        import("lib/periodic_table/trends"),
        import("lib/periodic_table/compounds")
      ])
    } catch {
      this.panelTargets.forEach((p) => { if (!p.hidden) p.innerHTML = `<p class="pb-error">Couldn't load the bench tools. Reload the page to try again.</p>` })
      return
    }
    if (this._disconnected) return
    this.ctxBase = { elements, bySymbol: chem.indexElements(elements), chem, trends, compounds }
    this._renderTray()
    this._activate(this.active)
  }

  _ctx() {
    return {
      ...this.ctxBase,
      tray: [...this.tray],
      emit: (name, detail) => this.root.dispatchEvent(new CustomEvent(name, { detail })),
      openElement: (number) => this.root.dispatchEvent(new CustomEvent("periodic-table:navigate", { detail: { number } })),
      highlight: (numbers, label) => this.root.dispatchEvent(new CustomEvent("periodic-table:highlight", { detail: { numbers, label } })),
      setTray: (symbols) => this.root.dispatchEvent(new CustomEvent("periodic-table:tray-set", { detail: { symbols } })),
      openTab: (tab, opts) => this._open({ tab, ...opts })
    }
  }

  // ── Tray ────────────────────────────────────────────────────────────
  _trayChanged(symbols) {
    this.tray = symbols
    this._renderTray()
    if (!this.ctxBase) return
    const ctx = this._ctx()
    this.mounted.forEach((m) => m.instance?.update?.(ctx))
  }

  _renderTray() {
    if (!this.hasTrayTarget) return
    const bySymbol = this.ctxBase?.bySymbol
    const chips = this.tray
      .map((s) => {
        const el = bySymbol?.get(s)
        return `<span class="ptable-tray-chip" data-category="${el?.category ?? "unknown"}">
          <button type="button" class="ptable-tray-open" data-action="click->periodic-bench#openFromTray" data-number="${el?.number ?? ""}" title="Open ${el?.name ?? s}" aria-label="Open ${el?.name ?? s} details">
            <b>${s}</b><small>${el?.name ?? ""}</small>
          </button>
          <button type="button" class="ptable-tray-remove" data-action="click->periodic-bench#removeFromTray" data-symbol="${s}" aria-label="Remove ${el?.name ?? s} from tray">×</button>
        </span>`
      })
      .join("")
    this.trayTarget.innerHTML = `
      <span class="ptable-tray-label">Tray</span>
      ${chips || `<span class="ptable-tray-empty">Tray is empty. Shift-click an element (or focus one and press <kbd>+</kbd>), or type symbols like Fe Ni Cr, then pick a tool below.</span>`}
      <form class="ptable-tray-add" data-action="submit->periodic-bench#addFromInput">
        <input type="text" name="symbols" placeholder="Add: Fe Ni Cr" aria-label="Add element symbols to tray" autocomplete="off" spellcheck="false">
      </form>
      ${this.tray.length ? `<button type="button" class="ptable-ghost-btn" data-action="click->periodic-bench#clearTray">Clear</button>` : ""}`
  }

  openFromTray(event) {
    const number = Number(event.currentTarget.dataset.number)
    if (number) this.root.dispatchEvent(new CustomEvent("periodic-table:navigate", { detail: { number } }))
  }

  removeFromTray(event) {
    this.root.dispatchEvent(new CustomEvent("periodic-table:tray-toggle", { detail: { symbol: event.currentTarget.dataset.symbol } }))
  }

  clearTray() {
    this.root.dispatchEvent(new CustomEvent("periodic-table:tray-set", { detail: { symbols: [] } }))
  }

  addFromInput(event) {
    event.preventDefault()
    const input = event.currentTarget.elements.symbols
    const bySymbol = this.ctxBase?.bySymbol
    const wanted = (input.value.match(/[A-Z][a-z]?/g) || []).filter((s) => bySymbol?.has(s) && !["D", "T"].includes(s))
    if (wanted.length) this.root.dispatchEvent(new CustomEvent("periodic-table:tray-set", { detail: { symbols: [...this.tray, ...wanted] } }))
    input.value = ""
  }

  // ── Tabs ────────────────────────────────────────────────────────────
  selectTab(event) {
    this._activate(event.currentTarget.dataset.tab)
  }

  tabKeydown(event) {
    const tabs = this.tabTargets
    const idx = tabs.indexOf(document.activeElement)
    if (idx === -1) return
    const map = { ArrowRight: idx + 1, ArrowLeft: idx - 1, Home: 0, End: tabs.length - 1 }
    if (!(event.key in map)) return
    event.preventDefault()
    const next = tabs[(map[event.key] + tabs.length) % tabs.length]
    this._activate(next.dataset.tab)
    next.focus()
  }

  _paintTabs() {
    this.tabTargets.forEach((t) => {
      const on = t.dataset.tab === this.active
      t.setAttribute("aria-selected", String(on))
      t.tabIndex = on ? 0 : -1
    })
    this.panelTargets.forEach((p) => { p.hidden = p.dataset.panel !== this.active })
  }

  async _activate(tab, opts = {}) {
    if (!INSTRUMENTS[tab]) tab = "combine"
    this.active = tab
    this._paintTabs()
    this._saveActive()
    if (!this.ctxBase) return
    const panel = this.panelTargets.find((p) => p.dataset.panel === tab)
    let entry = this.mounted.get(tab)
    if (!entry) {
      panel.innerHTML = `<p class="pb-loading">Loading instrument…</p>`
      const [path, fn] = INSTRUMENTS[tab]
      try {
        const mod = await import(path)
        if (this._disconnected) return
        entry = { instance: mod[fn](panel, this._ctx()) }
        this.mounted.set(tab, entry)
      } catch {
        panel.textContent = ""
        const msg = document.createElement("p")
        msg.className = "pb-error"
        msg.textContent = "Couldn't load this instrument. Switch tabs and back, or reload the page."
        panel.append(msg)
        return
      }
    }
    entry.instance?.focus?.(opts)
  }

  _open({ tab, ...opts }) {
    if (!tab) return
    this._activate(tab, opts)
    this.element.scrollIntoView({ behavior: window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" })
  }

  _loadActive() {
    try {
      return localStorage.getItem(LS_KEY) || "combine"
    } catch {
      return "combine"
    }
  }

  _saveActive() {
    try {
      localStorage.setItem(LS_KEY, this.active)
    } catch {
      // ponytail: best-effort persistence
    }
  }
}
