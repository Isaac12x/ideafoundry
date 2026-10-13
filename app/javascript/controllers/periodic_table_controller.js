import { Controller } from "@hotwired/stimulus"

const LS_KEY = "ptable:prefs"
const DISCOVERY_START = -9000
const DISCOVERY_END = 2010

const CATEGORY_INFO = {
  "alkali-metal": "Group 1 metals (not H): one s electron, soft, react violently with water to form strong bases.",
  "alkaline-earth-metal": "Group 2: two s electrons, harder and less reactive than alkali metals; form 2+ ions and basic oxides.",
  "transition-metal": "d-block: partly filled d subshells give variable oxidation states, coloured compounds, catalysis and magnetism.",
  "post-transition-metal": "Softer, lower-melting p-block metals (Al, Ga, In, Sn, Tl, Pb, Bi) with more covalent bonding.",
  metalloid: "Straddle the metal–nonmetal line; semiconductors (B, Si, Ge, As, Sb, Te).",
  "reactive-nonmetal": "H, C, N, O, P, S, Se and the halogens: gain or share electrons; form molecules and anions.",
  "noble-gas": "Full valence shells — monatomic, nearly inert; Xe and Kr form compounds with F and O.",
  lanthanide: "4f series La–Lu: chemically near-identical 3+ ions, hard to separate; magnets, phosphors, lasers.",
  actinide: "5f series Ac–Lr: all radioactive; early members (Th–Pu) show many oxidation states; nuclear fuel.",
  unknown: "Superheavy elements made a few atoms at a time; chemistry predicted, mostly unmeasured."
}

// Connects to data-controller="periodic-table"
//
// Owns the grid, toolbar, contextual strips, legend, search, keyboard nav,
// selection tray and the detail-panel host. Data (elements.mjs, details) and
// pure logic (trends.mjs) are dynamically imported. The nested bench
// (periodic_bench_controller) talks to this controller through DOM events:
//   ← periodic-table:navigate {number}        open an element's detail
//   ← periodic-table:highlight {numbers,label} dim everything else
//   ← periodic-table:tray-set {symbols}        replace the tray
//   ← periodic-table:tray-toggle {symbol}      add/remove one symbol
//   ← periodic-table:set-mode {mode, property} switch display mode
//   → periodic-table:tray-change {symbols}     (dispatched on this.element)
//   → periodic-table:ready {elements}
export default class extends Controller {
  static targets = [
    "search", "modeBtn", "propertySelect", "layoutBtn", "explain",
    "trendsStrip", "tempStrip", "tempSlider", "tempReadout", "unitBtn",
    "discoveryStrip", "discoveryPlay", "discoverySlider", "discoveryReadout", "discoveryTicker",
    "grid", "inspector", "detail", "legend", "highlightBanner", "highlightLabel"
  ]

  connect() {
    const prefs = this._loadPrefs()
    this.mode = prefs.mode || "series"
    this.layout = prefs.layout || "compact"
    this.unit = prefs.unit || "K"
    this.property = prefs.property || "electronegativity"
    this.tray = Array.isArray(prefs.tray) ? prefs.tray.slice(0, 12) : []
    this.tempK = 298
    this.discoveryYear = DISCOVERY_END
    this.selected = null
    this._ready = false
    this._cleanupDetail = null
    this._playTimer = null
    this._pinnedClass = null
    this._hoverClass = null
    this._highlight = null
    this._disconnected = false
    this._newlyKnownTimers = new Set()

    this.element.dataset.layout = this.layout
    this.element.dataset.mode = this.mode
    this._reflectModeUI()

    this._listeners = {
      "periodic-table:navigate": (e) => {
        const entry = this.tileByNumber?.get(e.detail.number)
        if (entry) this._openDetail(entry.el)
      },
      "periodic-table:close": () => this._closeDetail(),
      "periodic-table:highlight": (e) => this._setHighlight(e.detail?.numbers ?? null, e.detail?.label ?? ""),
      "periodic-table:tray-set": (e) => this._setTray(e.detail?.symbols ?? []),
      "periodic-table:tray-toggle": (e) => this._toggleTray(e.detail?.symbol),
      "periodic-table:set-mode": (e) => {
        if (e.detail?.property && this.trends?.PROPERTIES[e.detail.property]) this.property = e.detail.property
        if (e.detail?.mode) this.mode = e.detail.mode
        if (this.hasPropertySelectTarget) this.propertySelectTarget.value = this.property
        this._applyMode()
        this.element.scrollIntoView({ behavior: this._scrollBehavior(), block: "start" })
      }
    }
    for (const [name, fn] of Object.entries(this._listeners)) this.element.addEventListener(name, fn)

    this._onKeydown = (event) => this._handleGlobalKeydown(event)
    document.addEventListener("keydown", this._onKeydown)

    // Lazy init: the tab panel starts hidden, so don't fetch data or build
    // 118 tiles until Basics actually becomes visible — including landing
    // directly on #basics, where the panel is already visible by the time we
    // connect (the tabs controller runs first and removes .hidden).
    this._panel = this.element.closest("[data-tab-panel]")
    if (!this._panel || !this._panel.classList.contains("hidden")) {
      this._init()
    } else {
      this._panelObserver = new MutationObserver(() => {
        if (!this._panel.classList.contains("hidden")) {
          this._panelObserver.disconnect()
          this._init()
        }
      })
      this._panelObserver.observe(this._panel, { attributes: true, attributeFilter: ["class"] })
    }
  }

  disconnect() {
    this._panelObserver?.disconnect()
    for (const [name, fn] of Object.entries(this._listeners)) this.element.removeEventListener(name, fn)
    document.removeEventListener("keydown", this._onKeydown)
    this._cleanupDetail?.()
    this._cleanupDetail = null
    clearInterval(this._playTimer)
    this._playTimer = null
    clearTimeout(this._entranceTimer)
    this._newlyKnownTimers?.forEach(clearTimeout)
    this._disconnected = true
  }

  _scrollBehavior() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
  }

  async _init() {
    if (this._ready) return
    this._ready = true

    let ELEMENTS, CATEGORIES, trends
    try {
      ;[{ ELEMENTS, CATEGORIES }, trends] = await Promise.all([
        import("lib/periodic_table/elements"),
        import("lib/periodic_table/trends")
      ])
    } catch {
      this._ready = false
      if (this.hasExplainTarget) this.explainTarget.textContent = "Couldn't load the periodic table data. Reload the page to try again."
      return
    }
    if (this._disconnected) return
    this.elements = ELEMENTS
    this.categories = CATEGORIES
    this.trends = trends
    this.bySymbol = new Map(ELEMENTS.map((el) => [el.symbol, el]))
    this.tray = this.tray.filter((s) => this.bySymbol.has(s))

    this._fillPropertySelect()
    this._buildGrid()
    this._applyMode()
    this._applyTemp()
    this._applyDiscovery()
    this._updateInspector(null)
    this._paintTray()
    this._entranceAnimate()
    this.element.dispatchEvent(new CustomEvent("periodic-table:ready", { detail: { elements: ELEMENTS } }))
    this._emitTray()
  }

  // ── Grid construction (once) ─────────────────────────────────────────
  // Column 1 / row 1 hold the period and group axis labels, so element
  // positions are offset by one.
  _buildGrid() {
    const frag = document.createDocumentFragment()
    this.tileByNumber = new Map()

    this.elements.forEach((el) => {
      const tile = document.createElement("button")
      tile.type = "button"
      tile.className = "ptable-tile"
      tile.tabIndex = -1
      tile.dataset.number = el.number
      tile.dataset.category = el.category
      tile.style.setProperty("--gx", el.xpos + 1)
      tile.style.setProperty("--gy", el.ypos + 1)
      tile.style.setProperty("--wgx", (el.wxpos ?? el.xpos) + 1)
      tile.style.setProperty("--wgy", (el.wypos ?? el.ypos) + 1)
      tile.style.setProperty("--stagger", el.xpos + el.ypos)
      const categoryLabel = this.categories[el.category]?.label ?? el.category
      tile.setAttribute("aria-label", `${el.name}, atomic number ${el.number}, ${categoryLabel}`)
      const weight = el.atomicWeightBracketed ? `[${Math.round(el.mass)}]` : this._fmtWeight(el.mass)
      tile.innerHTML = `
        <span class="ptable-tile-top"><span class="ptable-tile-number">${el.number}</span><span class="ptable-tile-mass">${weight}</span></span>
        <span class="ptable-tile-symbol">${el.symbol}</span>
        <span class="ptable-tile-name">${el.name}</span>
        <span class="ptable-tile-sub"></span>
        <span class="ptable-tile-cat">${categoryLabel}</span>
      `
      frag.appendChild(tile)
      this.tileByNumber.set(el.number, { el, tile })
    })

    frag.appendChild(this._placeholder("57–71", 4, 7, "La–Lu"))
    frag.appendChild(this._placeholder("89–103", 4, 8, "Ac–Lr"))

    // Group numbers (IUPAC 1–18) across the top, periods down the side. In the
    // 32-column layout each group sits where its period-6 member sits.
    for (let g = 1; g <= 18; g++) {
      const p6 = this.elements.find((el) => el.group === g && el.period === 6)
      frag.appendChild(this._axisLabel(String(g), g + 1, 1, (p6?.wxpos ?? g) + 1, 1, "group"))
    }
    for (let p = 1; p <= 7; p++) frag.appendChild(this._axisLabel(String(p), 1, p + 1, 1, p + 1, "period"))
    frag.appendChild(this._axisLabel("Ln", 1, 10, null, null, "series"))
    frag.appendChild(this._axisLabel("An", 1, 11, null, null, "series"))

    this.gridTarget.appendChild(frag)
    this.tileEls = Array.from(this.gridTarget.querySelectorAll(".ptable-tile"))
    if (this.tileEls[0]) this.tileEls[0].tabIndex = 0
  }

  _axisLabel(text, gx, gy, wgx, wgy, kind) {
    const span = document.createElement("span")
    span.className = `ptable-axis ptable-axis--${kind}`
    span.style.setProperty("--gx", gx)
    span.style.setProperty("--gy", gy)
    if (wgx == null) span.classList.add("ptable-axis--compact-only")
    else {
      span.style.setProperty("--wgx", wgx)
      span.style.setProperty("--wgy", wgy)
    }
    span.textContent = text
    span.setAttribute("aria-hidden", "true")
    return span
  }

  _placeholder(label, gx, gy, title) {
    const div = document.createElement("div")
    div.className = "ptable-placeholder"
    div.style.setProperty("--gx", gx)
    div.style.setProperty("--gy", gy)
    div.innerHTML = `<span>${label}</span><small>${title}</small>`
    div.setAttribute("aria-hidden", "true")
    return div
  }

  _fmtWeight(w) {
    if (w == null) return ""
    return w >= 100 ? w.toFixed(2) : w >= 10 ? w.toFixed(3) : w.toFixed(4).replace(/0+$/, "").replace(/\.$/, "")
  }

  _entranceAnimate() {
    this.gridTarget.classList.add("is-entering")
    this._entranceTimer = setTimeout(() => this.gridTarget.classList.remove("is-entering"), 1800)
  }

  _fillPropertySelect() {
    if (!this.hasPropertySelectTarget) return
    const { PROPERTIES, PROPERTY_GROUPS } = this.trends
    this.propertySelectTarget.innerHTML = PROPERTY_GROUPS.map((group) => {
      const opts = Object.entries(PROPERTIES)
        .filter(([, p]) => p.group === group)
        .map(([key, p]) => `<option value="${key}">${p.label}${p.unit ? ` (${p.unit})` : ""}</option>`)
        .join("")
      return `<optgroup label="${group}">${opts}</optgroup>`
    }).join("")
    if (!PROPERTIES[this.property]) this.property = "electronegativity"
    this.propertySelectTarget.value = this.property
  }

  // ── Modes ─────────────────────────────────────────────────────────────
  setMode(event) {
    this.mode = event.currentTarget.dataset.mode
    this._applyMode()
  }

  _modeMeta() {
    return this.trends?.MODES.find((m) => m.key === this.mode) ?? { key: this.mode }
  }

  _activeLens() {
    if (!this.trends) return null
    if (this.mode === "discovery") return this.trends.LENSES.discoveryMethod
    const meta = this._modeMeta()
    return meta.lens ? this.trends.LENSES[meta.lens] : null
  }

  _applyMode() {
    this.element.dataset.mode = this.mode
    const lens = this._activeLens()
    this.element.dataset.modeKind = lens ? "lens" : this.mode
    this._pinnedClass = null
    this._hoverClass = null
    this._reflectModeUI()
    if (this.mode !== "discovery") this._stopDiscoveryPlay()

    if (this.trends && this.mode === "trends") {
      const meta = this.trends.PROPERTIES[this.property]
      this._scale = this.trends.scale(this.elements, this.property, { log: !!meta?.log })
    }

    this._repaintTiles()
    this._buildLegend()
    this._applyDim()
    this._renderExplain()
    if (this.selected) this._updateInspector(this.selected)
    this._savePrefs()
  }

  _reflectModeUI() {
    this.modeBtnTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.mode === this.mode)))
    this.layoutBtnTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.layout === this.layout)))
    this.unitBtnTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.unit === this.unit)))
    if (this.hasPropertySelectTarget && this.trends) this.propertySelectTarget.value = this.property
    if (this.hasTrendsStripTarget) this.trendsStripTarget.hidden = this.mode !== "trends"
    if (this.hasTempStripTarget) this.tempStripTarget.hidden = this.mode !== "state"
    if (this.hasDiscoveryStripTarget) this.discoveryStripTarget.hidden = this.mode !== "discovery"
  }

  _renderExplain() {
    if (!this.hasExplainTarget || !this.trends) return
    const meta = this._modeMeta()
    let text = meta.explain
    if (meta.lens) text = this.trends.LENSES[meta.lens].explain
    if (this.mode === "trends") text = this.trends.PROPERTIES[this.property]?.trend
    if (this.mode === "discovery") text = `${meta.explain}`
    this.explainTarget.textContent = text || ""
  }

  _repaintTiles() {
    this.tileByNumber?.forEach(({ el, tile }) => this._paintTile(el, tile))
  }

  _paintTile(el, tile) {
    const sub = tile.querySelector(".ptable-tile-sub")
    const lens = this._activeLens()
    tile.classList.remove("ptable-tile--nodata")
    tile.removeAttribute("data-hot")
    if (lens) {
      const cls = lens.of(el)
      tile.dataset.cls = cls
      tile.style.setProperty("--cls", lens.classes[cls]?.color ?? "oklch(45% 0.01 280)")
    } else {
      delete tile.dataset.cls
      tile.style.removeProperty("--cls")
    }

    switch (this.mode) {
      case "trends": {
        const value = this.trends.propertyAccessor(this.property)(el)
        const norm = this._scale?.norm(value)
        tile.classList.toggle("ptable-tile--nodata", norm == null)
        tile.style.setProperty("--heat", norm == null ? 0 : norm)
        tile.toggleAttribute("data-hot", norm != null && norm > 0.62)
        sub.textContent = value == null ? "—" : this.trends.formatValue(value)
        break
      }
      case "state":
        tile.dataset.state = this.trends.stateAt(el, this.tempK)
        sub.textContent = tile.dataset.state === "unknown" ? "" : tile.dataset.state
        break
      case "discovery": {
        const known = this.trends.knownBy(el, this.discoveryYear)
        const wasKnown = tile.dataset.known === "true"
        tile.dataset.known = String(known)
        if (known && !wasKnown && this._playTimer) {
          tile.classList.add("is-newly-known")
          const timer = setTimeout(() => { this._newlyKnownTimers.delete(timer); tile.classList.remove("is-newly-known") }, 900)
          this._newlyKnownTimers.add(timer)
        }
        sub.textContent = el.ancient ? "ancient" : el.yearDiscovered ?? ""
        break
      }
      case "electrons":
        sub.textContent = (el.electronConfig ?? "").replace(/^\*/, "")
        break
      case "isotopes": {
        const s = el.isotopeSummary?.stable ?? 0
        tile.dataset.stable = s > 0 ? "yes" : "no"
        sub.textContent = s ? `${s} stable` : `0 stable · ${el.isotopesKnown ?? 0} known`
        break
      }
      case "oxidation": {
        const main = new Set(el.oxidationMain || [])
        const shown = (el.oxidationMain?.length ? el.oxidationMain : el.oxidationStates || []).slice(0, 4)
        sub.textContent = shown.length ? shown.map((s) => (s > 0 ? `+${s}` : `${s}`)).join(" ") : "—"
        tile.title = el.oxidationStates?.length ? `Main: ${[...main].join(", ")} · all: ${el.oxidationStates.join(", ")}` : ""
        break
      }
      case "valence":
        sub.textContent = el.valence != null ? `${el.valence} e⁻` : "—"
        break
      case "crystal":
        sub.textContent = el.latticeStructure ?? ""
        break
      case "magnetic":
        sub.textContent = { ferro: "ferro", antiferro: "AFM", para: "para", dia: "dia" }[el.magnetic?.ordering] ?? ""
        break
      case "goldschmidt":
        sub.textContent = (el.goldschmidt ?? "").replace(/phile$/, "")
        break
      case "block":
        sub.textContent = `${el.block}-block`
        break
      default:
        sub.textContent = ""
    }
  }

  setProperty(event) {
    this.property = event.target.value
    this._applyMode()
  }

  plotProperty() {
    this.element.dispatchEvent(new CustomEvent("periodic-bench:open", { detail: { tab: "plot", property: this.property } }))
  }

  setLayout(event) {
    this.layout = event.currentTarget.dataset.layout
    this.element.dataset.layout = this.layout
    this.layoutBtnTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.layout === this.layout)))
    this._savePrefs()
  }

  print() {
    window.print()
  }

  // ── Temperature ───────────────────────────────────────────────────────
  setTemp(event) {
    this.tempK = Number(event.target.value)
    this._applyTemp()
  }

  _applyTemp() {
    if (!this.trends) return
    if (this.hasTempReadoutTarget) {
      const k = Math.round(this.tempK)
      this.tempReadoutTarget.textContent = this.unit === "K" ? `${k} K` : `${this.trends.formatTemp(this.tempK, this.unit)} · ${k} K`
    }
    if (this.mode === "state") {
      this._repaintTiles()
      this._buildLegend()
    }
  }

  setUnit(event) {
    this.unit = event.currentTarget.dataset.unit
    this.unitBtnTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.unit === this.unit)))
    this._applyTemp()
    this._savePrefs()
  }

  // ── Discovery timeline ───────────────────────────────────────────────
  setDiscoveryYear(event) {
    this.discoveryYear = Number(event.target.value)
    this._applyDiscovery()
  }

  _yearLabel(y) {
    return y < 0 ? `${-y} BCE` : `${y}`
  }

  _applyDiscovery() {
    if (!this.trends || !this.elements) return
    if (this.mode === "discovery") {
      this._repaintTiles()
      this._buildLegend()
    }

    const known = this.elements.filter((el) => this.trends.knownBy(el, this.discoveryYear)).length
    if (this.hasDiscoveryReadoutTarget) {
      this.discoveryReadoutTarget.textContent = `${this._yearLabel(this.discoveryYear)} · ${known} known`
    }
    if (this.hasDiscoveryTickerTarget) {
      const window = this._playTimer ? 40 : 0
      const found = this.elements.filter((el) => {
        const y = el.ancient ? el.earliestUse : el.yearDiscovered
        return y != null && y <= this.discoveryYear && y >= this.discoveryYear - window
      })
      this.discoveryTickerTarget.textContent = found.length
        ? found.slice(-3).map((el) => `${el.symbol} — ${el.discoveredBy || "unknown"}, ${el.discoveryPlace || ""}`).join("  ·  ")
        : ""
    }
  }

  toggleDiscoveryPlay() {
    if (this._playTimer) { this._stopDiscoveryPlay(); return }

    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
      this.discoveryYear = DISCOVERY_END
      this.discoverySliderTarget.value = DISCOVERY_END
      this._applyDiscovery()
      return
    }

    this._setPlayIcon(true)
    if (this.discoveryYear >= DISCOVERY_END) {
      this.discoveryYear = DISCOVERY_START
      this.discoverySliderTarget.value = DISCOVERY_START
    }
    // Time is compressed before 1600 (few events) and slowed after (most).
    this._playTimer = setInterval(() => {
      const step = this.discoveryYear < 0 ? 120 : this.discoveryYear < 1600 ? 40 : this.discoveryYear < 1950 ? 3 : 2
      this.discoveryYear = Math.min(DISCOVERY_END, this.discoveryYear + step)
      this.discoverySliderTarget.value = this.discoveryYear
      this._applyDiscovery()
      if (this.discoveryYear >= DISCOVERY_END) this._stopDiscoveryPlay()
    }, 60)
  }

  _stopDiscoveryPlay() {
    clearInterval(this._playTimer)
    this._playTimer = null
    this._setPlayIcon(false)
  }

  _setPlayIcon(playing) {
    if (!this.hasDiscoveryPlayTarget) return
    this.discoveryPlayTarget.textContent = playing ? "❚❚" : "▶"
    this.discoveryPlayTarget.setAttribute("aria-label", playing ? "Pause discovery timeline" : "Play discovery timeline")
  }

  // ── Search ───────────────────────────────────────────────────────────
  _matches(el, query) {
    const q = query.toLowerCase()
    return el.symbol.toLowerCase() === q
      || el.symbol.toLowerCase().startsWith(q)
      || el.name.toLowerCase().includes(q)
      || String(el.number) === q
      || (el.cas && el.cas === query)
  }

  search(event) {
    const query = event.target.value.trim()
    this._searchMiss = query ? new Set() : null
    if (query) this.elements.forEach((el) => { if (!this._matches(el, query)) this._searchMiss.add(el.number) })
    this._applyDim()
  }

  searchKeydown(event) {
    if (event.key === "Escape") {
      event.target.value = ""
      this.search(event)
      return
    }
    if (event.key !== "Enter") return
    const query = event.target.value.trim().toLowerCase()
    if (!query) return
    const exact = this.elements.find((el) =>
      el.symbol.toLowerCase() === query || el.name.toLowerCase() === query || String(el.number) === query || el.cas === query
    )
    const fallback = exact || this.elements.find((el) => !this._searchMiss?.has(el.number))
    if (fallback) this._openDetail(fallback)
  }

  // ── Highlight (driven by the bench) ─────────────────────────────────
  _setHighlight(numbers, label) {
    this._highlight = numbers && numbers.length ? new Set(numbers) : null
    if (this.hasHighlightBannerTarget) {
      this.highlightBannerTarget.hidden = !this._highlight
      this.highlightLabelTarget.textContent = this._highlight ? label : ""
    }
    this._applyDim()
  }

  clearHighlight() {
    this._setHighlight(null, "")
    this.element.dispatchEvent(new CustomEvent("periodic-table:highlight-cleared", { bubbles: false }))
  }

  // ── Legend + class filter ───────────────────────────────────────────
  legendInteract(event) {
    const chip = event.target.closest("[data-legend-class]")
    if (!chip) return
    const key = chip.dataset.legendClass
    if (event.type === "click") {
      this._pinnedClass = this._pinnedClass === key ? null : key
      this.legendTarget.querySelectorAll("[data-legend-class]").forEach((c) => {
        c.classList.toggle("is-pinned", c.dataset.legendClass === this._pinnedClass)
        c.setAttribute("aria-pressed", String(c.dataset.legendClass === this._pinnedClass))
      })
    } else if (event.type === "mouseover" || event.type === "focusin") {
      this._hoverClass = key
      this._showLegendNote(chip.dataset.note)
    } else if (event.type === "mouseout") {
      this._hoverClass = null
      this._showLegendNote(null)
    }
    this._applyDim()
  }

  _showLegendNote(text) {
    const note = this.legendTarget.querySelector(".ptable-legend-note")
    if (note) note.textContent = text || note.dataset.default || ""
  }

  _classOf(el) {
    const lens = this._activeLens()
    if (lens) return lens.of(el)
    if (this.mode === "state") return this.trends.stateAt(el, this.tempK)
    if (this.mode === "isotopes") return el.isotopeSummary?.stable > 0 ? "stable" : "unstable"
    return el.category
  }

  _applyDim() {
    const active = this._hoverClass || this._pinnedClass
    this.tileByNumber?.forEach(({ el, tile }) => {
      const searchDim = this._searchMiss?.has(el.number)
      const classDim = active && this._classOf(el) !== active
      const highlightDim = this._highlight && !this._highlight.has(el.number)
      tile.classList.toggle("ptable-tile--dim", !!(searchDim || classDim || highlightDim))
    })
  }

  _buildLegend() {
    if (!this.hasLegendTarget || !this.categories) return
    let html
    if (this.mode === "trends") html = this._legendRamp()
    else if (this.mode === "state") html = this._legendChips(this._stateClasses(), "State at the selected temperature")
    else if (this.mode === "isotopes") html = this._legendChips({
      stable: { label: "Has stable isotopes", color: "var(--accent)", desc: "At least one isotope never observed to decay." },
      unstable: { label: "Only radioactive", color: "oklch(60% 0.12 25)", desc: "Every isotope decays — Tc, Pm and everything above Pb." }
    }, "Hover a class to isolate it; click to pin")
    else {
      const lens = this._activeLens()
      html = lens
        ? this._legendChips(lens.classes, lens.label)
        : this._legendChips(Object.fromEntries(Object.entries(this.categories).map(([k, v]) => [k, { label: v.label, color: `var(--cat-${k})`, desc: CATEGORY_INFO[k] }])), "Chemical series — hover for a definition, click to pin")
    }
    this.legendTarget.innerHTML = html + this._legendAnatomy()
    this._rampEl = this.legendTarget.querySelector(".ptable-legend-ramp")
  }

  _stateClasses() {
    return {
      solid: { label: "Solid", color: "oklch(70% 0.06 80)", desc: "Below the melting point." },
      liquid: { label: "Liquid", color: "oklch(66% 0.12 230)", desc: "Between melting and boiling points." },
      gas: { label: "Gas", color: "oklch(78% 0.06 180)", desc: "At or above the boiling (or sublimation) point." },
      unknown: { label: "Unknown", color: "oklch(45% 0.01 280)", desc: "Melting/boiling points not measured." }
    }
  }

  _legendChips(classes, title) {
    const counts = {}
    this.elements.forEach((el) => {
      const c = this._classOf(el)
      counts[c] = (counts[c] || 0) + 1
    })
    const chips = Object.entries(classes)
      .filter(([key]) => counts[key])
      .map(([key, c]) => `
        <button type="button" class="ptable-legend-chip${this._pinnedClass === key ? " is-pinned" : ""}" data-legend-class="${key}"
                style="--cls:${c.color}" data-note="${(c.desc || "").replace(/"/g, "&quot;")}" aria-pressed="${this._pinnedClass === key}">
          <span class="ptable-legend-swatch" aria-hidden="true"></span>${c.label}<span class="ptable-legend-count">${counts[key]}</span>
        </button>`).join("")
    return `
      <div class="ptable-legend-main">
        <p class="ptable-legend-title">${title}</p>
        <div class="ptable-legend-chips">${chips}</div>
        <p class="ptable-legend-note" data-default="Hover a class for its definition · click to isolate it on the table">Hover a class for its definition · click to isolate it on the table</p>
      </div>`
  }

  _legendRamp() {
    const meta = this.trends.PROPERTIES[this.property]
    const fmt = (v) => this.trends.formatValue(v, meta?.unit)
    const extremes = this._extremes()
    return `
      <div class="ptable-legend-main">
        <p class="ptable-legend-title">${meta?.label ?? ""}${meta?.log ? " · log scale" : ""} · ${this._scale?.count ?? 0} of 118 measured</p>
        <div class="ptable-legend-ramp-wrap">
          <span class="ptable-legend-min">${this._scale ? fmt(this._scale.min) : ""}</span>
          <div class="ptable-legend-ramp"><span class="ptable-legend-marker" hidden></span></div>
          <span class="ptable-legend-max">${this._scale ? fmt(this._scale.max) : ""}</span>
        </div>
        <p class="ptable-legend-note">Lowest: ${extremes.low} · Highest: ${extremes.high} · hatched tiles have no measured value</p>
      </div>`
  }

  _extremes() {
    const acc = this.trends.propertyAccessor(this.property)
    const vals = this.elements.map((el) => [el, acc(el)]).filter(([, v]) => v != null && Number.isFinite(v))
    vals.sort((a, b) => a[1] - b[1])
    const name = (pair) => (pair ? `${pair[0].symbol} (${this.trends.formatValue(pair[1])})` : "—")
    return { low: name(vals[0]), high: name(vals[vals.length - 1]) }
  }

  // Tile anatomy key — always visible so every number on a tile is explained.
  _legendAnatomy() {
    const readout = {
      trends: this.trends.PROPERTIES[this.property]?.label ?? "property value",
      state: "phase at the chosen temperature",
      discovery: "year discovered",
      electrons: "electron configuration",
      oxidation: "main oxidation states",
      valence: "valence electrons",
      isotopes: "stable isotope count",
      crystal: "lattice structure",
      magnetic: "magnetic ordering",
      goldschmidt: "Goldschmidt class",
      block: "orbital block"
    }[this.mode] ?? "mode readout"
    return `
      <figure class="ptable-anatomy" aria-label="How to read a tile">
        <div class="ptable-anatomy-tile" aria-hidden="true">
          <span class="a-num">26</span><span class="a-mass">55.845</span>
          <span class="a-sym">Fe</span><span class="a-name">Iron</span><span class="a-sub">${readout.length > 18 ? "value" : "readout"}</span>
        </div>
        <figcaption>
          <span><b>26</b> atomic number — protons in the nucleus</span>
          <span><b>55.845</b> standard atomic weight (u); <b>[ ]</b> = mass number of the most stable isotope</span>
          <span><b>Fe</b> symbol · <b>Iron</b> name</span>
          <span><b>bottom line</b> ${readout}</span>
          <span class="ptable-anatomy-tip">Shift-click or <kbd>+</kbd> adds to the tray · <kbd>Enter</kbd> opens details · arrows move</span>
        </figcaption>
      </figure>`
  }

  _updateRampMarker(el) {
    if (this.mode !== "trends" || !this._rampEl) return
    const marker = this._rampEl.querySelector(".ptable-legend-marker")
    if (!marker) return
    const value = this.trends.propertyAccessor(this.property)(el)
    const norm = this._scale?.norm(value)
    marker.hidden = norm == null
    if (norm != null) marker.style.setProperty("--pos", norm)
  }

  // ── Tray (multi-select shared with the bench) ───────────────────────
  _toggleTray(symbol) {
    if (!symbol || !this.bySymbol?.has(symbol)) return
    this.tray = this.tray.includes(symbol) ? this.tray.filter((s) => s !== symbol) : [...this.tray, symbol].slice(-12)
    this._afterTrayChange()
  }

  _setTray(symbols) {
    this.tray = [...new Set(symbols)].filter((s) => this.bySymbol?.has(s)).slice(0, 12)
    this._afterTrayChange()
  }

  _afterTrayChange() {
    this._paintTray()
    this._emitTray()
    this._savePrefs()
  }

  _paintTray() {
    const set = new Set(this.tray)
    this.tileByNumber?.forEach(({ el, tile }) => {
      tile.classList.toggle("is-tray", set.has(el.symbol))
      tile.dataset.trayIndex = set.has(el.symbol) ? this.tray.indexOf(el.symbol) + 1 : ""
    })
  }

  _emitTray() {
    this.element.dispatchEvent(new CustomEvent("periodic-table:tray-change", { detail: { symbols: [...this.tray] } }))
  }

  // ── Grid interaction (delegated) ────────────────────────────────────
  gridHover(event) {
    const tile = event.target.closest(".ptable-tile")
    if (!tile) return
    const entry = this.tileByNumber?.get(Number(tile.dataset.number))
    if (!entry) return
    this._updateInspector(entry.el)
    this._updateRampMarker(entry.el)
  }

  gridOut(event) {
    if (event.relatedTarget && this.gridTarget.contains(event.relatedTarget)) return
    this._updateInspector(this.selected)
  }

  gridClick(event) {
    const tile = event.target.closest(".ptable-tile")
    if (!tile) return
    const entry = this.tileByNumber?.get(Number(tile.dataset.number))
    if (!entry) return
    if (event.shiftKey || event.metaKey || event.ctrlKey) {
      event.preventDefault()
      this._toggleTray(entry.el.symbol)
      return
    }
    this._openDetail(entry.el)
  }

  gridKeydown(event) {
    const tile = event.target.closest(".ptable-tile")
    if (!tile) return
    const entry = this.tileByNumber?.get(Number(tile.dataset.number))

    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      if (entry) this._openDetail(entry.el)
      return
    }
    if (event.key === "+" || event.key === "=") {
      event.preventDefault()
      if (entry) this._toggleTray(entry.el.symbol)
      return
    }
    if (event.key === "Escape") { this._closeDetail(); return }

    const dirs = { ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] }
    const dir = dirs[event.key]
    if (!dir) return
    event.preventDefault()
    this._moveFocus(tile, dir)
  }

  _moveFocus(fromTile, [dx, dy]) {
    const gx = this.layout === "wide" ? "--wgx" : "--gx"
    const gy = this.layout === "wide" ? "--wgy" : "--gy"
    const fx = Number(fromTile.style.getPropertyValue(gx))
    const fy = Number(fromTile.style.getPropertyValue(gy))
    let best = null
    let bestDist = Infinity

    this.tileEls.forEach((tile) => {
      if (tile === fromTile) return
      const x = Number(tile.style.getPropertyValue(gx))
      const y = Number(tile.style.getPropertyValue(gy))
      if (dx !== 0) {
        if (y !== fy || Math.sign(x - fx) !== dx) return
      } else {
        if (x !== fx || Math.sign(y - fy) !== dy) return
      }
      const dist = Math.abs(x - fx) + Math.abs(y - fy)
      if (dist < bestDist) { bestDist = dist; best = tile }
    })

    if (best) {
      fromTile.tabIndex = -1
      best.tabIndex = 0
      best.focus()
    }
  }

  // ── Inspector (hover/focus preview; idle = how-to-read guide) ───────
  _updateInspector(el) {
    if (!this.hasInspectorTarget || !this.trends) return
    if (!el) {
      this.inspectorTarget.style.removeProperty("--cat")
      this.inspectorTarget.innerHTML = `
        <div class="ptable-inspector-idle">
          <p class="ptable-inspector-kicker">Reading the table</p>
          <p class="ptable-inspector-lede">Rows are <b>periods</b> — each adds an electron shell. Columns are <b>groups</b> — same outer electrons, so similar chemistry. Atomic number rises left to right, top to bottom.</p>
          <p class="ptable-inspector-hint">Hover an element to inspect it · shift-click to collect several for the bench below</p>
        </div>`
      return
    }
    const t = this.trends
    const categoryLabel = this.categories[el.category]?.label ?? el.category
    const state = t.stateAt(el, this.tempK)
    const weight = el.atomicWeightBracketed ? `[${Math.round(el.mass)}]` : this._fmtWeight(el.mass)
    const modeLine = (() => {
      if (this.mode === "trends") {
        const meta = t.PROPERTIES[this.property]
        return `${meta.label}: <b>${t.formatValue(t.propertyAccessor(this.property)(el), meta.unit)}</b>`
      }
      const lens = this._activeLens()
      if (lens) {
        const cls = lens.classes[lens.of(el)]
        return `${lens.label}: <b>${cls?.label ?? "—"}</b>`
      }
      return ""
    })()
    const discovered = el.ancient ? "known since antiquity" : el.yearDiscovered ? `discovered ${el.yearDiscovered}` : ""
    this.inspectorTarget.innerHTML = `
      <div class="ptable-inspector-card">
        <div class="ptable-inspector-glyph">
          <span class="ptable-inspector-number">${el.number}</span>
          <span class="ptable-inspector-symbol">${el.symbol}</span>
        </div>
        <div class="ptable-inspector-body">
          <span class="ptable-inspector-name">${el.name}</span>
          <span class="ptable-inspector-meta">${categoryLabel} · group ${el.group ?? "—"} · period ${el.period} · ${el.block}-block</span>
          ${modeLine ? `<span class="ptable-inspector-mode">${modeLine}</span>` : ""}
          <dl class="ptable-inspector-facts">
            <div><dt>Atomic weight</dt><dd>${weight} u</dd></div>
            <div><dt>Configuration</dt><dd>${(el.electronConfig || "—").replace(/^\*/, "")}</dd></div>
            <div><dt>χ (Pauling)</dt><dd>${el.electronegativity ?? "—"}</dd></div>
            <div><dt>At ${this.trends.formatTemp(this.tempK, this.unit)}</dt><dd>${state}</dd></div>
            <div><dt>Ox. states</dt><dd>${(el.oxidationMain || []).map((s) => (s > 0 ? `+${s}` : s)).join(", ") || "—"}</dd></div>
            <div><dt>History</dt><dd>${discovered}</dd></div>
          </dl>
        </div>
      </div>`
    this.inspectorTarget.style.setProperty("--cat", `var(--cat-${el.category})`)
  }

  // ── Detail panel (contract: lib/periodic_table/detail) ──────────────
  async _openDetail(el) {
    if (!el || !this.hasDetailTarget) return
    this._cleanupDetail?.()
    const token = (this._detailToken = (this._detailToken || 0) + 1)

    const idx = this.elements.findIndex((e) => e.number === el.number)
    const prev = idx > 0 ? this.elements[idx - 1] : null
    const next = idx < this.elements.length - 1 ? this.elements[idx + 1] : null

    let renderDetail, wireDetail, ELEMENT_DETAILS
    try {
      ;[{ renderDetail, wireDetail }, { ELEMENT_DETAILS }] = await Promise.all([
        import("lib/periodic_table/detail"),
        import("lib/periodic_table/element_details")
      ])
    } catch {
      if (this.hasExplainTarget) this.explainTarget.textContent = "Couldn't load element details. Check your connection and try again."
      return
    }
    if (this._disconnected || token !== this._detailToken) return
    this.selected = el
    this.detailTarget.style.setProperty("--cat", `var(--cat-${el.category})`)
    this.detailTarget.innerHTML = renderDetail(el, {
      tempK: this.tempK,
      unit: this.unit,
      categories: this.categories,
      neighbours: { prev: prev?.number, next: next?.number },
      details: ELEMENT_DETAILS[el.number] || {},
      elements: this.elements,
      inTray: this.tray.includes(el.symbol)
    })
    this._cleanupDetail = wireDetail(this.detailTarget, el)
    this.detailTarget.hidden = false
    this.element.classList.add("has-detail")

    this.tileByNumber?.forEach(({ tile }, number) => tile.classList.toggle("is-selected", number === el.number))
    this._updateInspector(el)
  }

  _closeDetail() {
    this._detailToken = (this._detailToken || 0) + 1
    this._cleanupDetail?.()
    this._cleanupDetail = null
    if (this.hasDetailTarget) {
      this.detailTarget.hidden = true
      this.detailTarget.innerHTML = ""
    }
    this.element.classList.remove("has-detail")
    this.tileByNumber?.forEach(({ tile }) => tile.classList.remove("is-selected"))
    const focusTile = this.selected && this.tileByNumber?.get(this.selected.number)?.tile
    this.selected = null
    this._updateInspector(null)
    focusTile?.focus({ preventScroll: true })
  }

  // ── Global keyboard ("/" focuses search, Esc closes detail) ─────────
  _handleGlobalKeydown(event) {
    if (!this.element.offsetParent) return // panel hidden — not our shortcut to steal
    const active = document.activeElement
    const typing = active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA" || active.tagName === "SELECT" || active.isContentEditable)
    if (event.key === "Escape" && this.selected && !typing) {
      this._closeDetail()
      return
    }
    if (event.key !== "/" || typing) return
    event.preventDefault()
    this.searchTarget.focus()
  }

  // ── Preferences ──────────────────────────────────────────────────────
  _loadPrefs() {
    try {
      return JSON.parse(localStorage.getItem(LS_KEY)) || {}
    } catch {
      return {}
    }
  }

  _savePrefs() {
    try {
      localStorage.setItem(LS_KEY, JSON.stringify({
        mode: this.mode, layout: this.layout, unit: this.unit, property: this.property, tray: this.tray
      }))
    } catch {
      // ponytail: best-effort persistence, ignore quota/privacy-mode failures
    }
  }
}
