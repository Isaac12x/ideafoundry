import { Controller } from "@hotwired/stimulus"

const COL_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

export default class extends Controller {
  static targets = ["body", "grid", "toggleBtn", "fmtSelect", "decimalsInput", "boldBtn",
                    "hiddenInput", "formulaBar", "formulaRef", "loading"]
  static values  = { initial: String, inputName: String, expanded: Boolean }

  connect() {
    const init = this.initialValue ? JSON.parse(this.initialValue) : { rows: 10, cols: 5, cells: {} }
    this.state = {
      rows: init.rows || 10,
      cols: init.cols || 5,
      cells: new Map(Object.entries(init.cells || {})),
      selection: { anchor: "A1", focus: "A1" }
    }
    this.hf = null
    this.hfSheetId = null
    this.hfSheetIndex = null
    this.parserLoading = false

    this.renderGrid()
    this.syncHiddenInput()
    if (this.expandedValue) this.ensureParserLoaded()

    this.element.addEventListener("keydown", (e) => {
      if (e.key === "Delete" || e.key === "Backspace") {
        if (e.target.tagName === "INPUT") return
        e.preventDefault()
        this.selectionCells().forEach((ref) => this.setCell(ref, { raw: "", fmt: null }))
        this.renderGrid()
      }
    })
    this.element.tabIndex = 0
  }

  toggle(e) {
    if (e && e.target.closest("input, select, button.napkin-toggle-btn") === null && e.currentTarget !== this.element.querySelector(".napkin-header")) return
    const isOpen = !this.bodyTarget.classList.contains("hidden")
    if (isOpen) {
      this.bodyTarget.classList.add("hidden")
      this.toggleBtnTarget.setAttribute("aria-expanded", "false")
    } else {
      this.bodyTarget.classList.remove("hidden")
      this.toggleBtnTarget.setAttribute("aria-expanded", "true")
      this.ensureParserLoaded()
    }
  }

  cellRef(c, r) { return `${COL_LETTERS[c]}${r + 1}` }
  parseRef(ref) {
    const m = /^([A-Z])(\d+)$/.exec(ref)
    return m ? { c: COL_LETTERS.indexOf(m[1]), r: parseInt(m[2], 10) - 1 } : null
  }

  renderGrid() {
    const { rows, cols, cells } = this.state
    const el = this.gridTarget
    let html = '<table class="napkin-grid-table"><thead><tr><th class="napkin-corner"></th>'
    for (let c = 0; c < cols; c++) html += `<th class="napkin-col-header">${COL_LETTERS[c]}</th>`
    html += "</tr></thead><tbody>"
    for (let r = 0; r < rows; r++) {
      html += `<tr><th class="napkin-row-header">${r + 1}</th>`
      for (let c = 0; c < cols; c++) {
        const ref = this.cellRef(c, r)
        const cell = cells.get(ref) || { raw: "", fmt: null }
        const display = this.computeDisplay(ref, cell)
        const cls = ["napkin-cell"]
        if (cell.fmt && cell.fmt.includes("bold")) cls.push("is-bold")
        if (display.error) cls.push("napkin-cell--error")
        if (this.isSelected(ref)) cls.push("is-selected")
        html += `<td class="${cls.join(" ")}" data-ref="${ref}" data-action="mousedown->napkin#cellMouseDown dblclick->napkin#editCell">${this.escape(display.text)}</td>`
      }
      html += "</tr>"
    }
    html += "</tbody></table>"
    el.innerHTML = html
    this.updateFormulaBar()
  }

  computeDisplay(ref, cell) {
    if (!cell || !cell.raw) return { text: "", error: null }
    if (cell.raw.startsWith("=")) {
      return this.hf ? this.evaluateFormula(ref, cell) : { text: cell.raw, error: null }
    }
    return { text: this.formatNumeric(cell.raw, cell.fmt), error: null }
  }

  formatNumeric(raw, fmt) {
    const n = Number(raw)
    if (Number.isNaN(n) || raw.trim() === "") return raw
    return this.formatValue(n, fmt)
  }

  formatValue(n, fmt) {
    const parts = (fmt || "").split("|").filter(p => p && p !== "bold")
    const style = parts[0]
    if (!style) return Number.isInteger(n) ? String(n) : String(n)
    const m1 = /^number:(\d+)$/.exec(style)
    if (m1) return n.toFixed(parseInt(m1[1], 10))
    const m2 = /^currency:([A-Z]{3}):(\d+)$/.exec(style)
    if (m2) {
      const sym = ({ USD: "$", EUR: "€", GBP: "£", JPY: "¥" })[m2[1]] || `${m2[1]} `
      const dec = parseInt(m2[2], 10)
      return `${sym}${n.toFixed(dec).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`
    }
    const m3 = /^percent:(\d+)$/.exec(style)
    if (m3) return `${(n * 100).toFixed(parseInt(m3[1], 10))}%`
    return String(n)
  }

  evaluateFormula(ref, cell) {
    if (!this.hf) return { text: cell.raw, error: null }
    const p = this.parseRef(ref)
    if (!p) return { text: "#REF", error: "#REF" }
    const value = this.hf.getCellValue({ sheet: this.hfSheetIndex, row: p.r, col: p.c })
    if (value && typeof value === "object" && value.type === "ERROR") {
      return { text: this.mapHFError(value), error: this.mapHFError(value) }
    }
    if (typeof value === "number") {
      return { text: this.formatValue(value, cell.fmt), error: null }
    }
    return { text: String(value ?? ""), error: null }
  }

  mapHFError(err) {
    const t = (err && err.value) || (err && err.error) || ""
    const s = String(t)
    if (s.includes("CYCLE")) return "#CYCLE"
    if (s.includes("REF")) return "#REF"
    if (s.includes("DIV")) return "#DIV/0"
    return "#ERR"
  }

  syncAllCellsToHF() {
    if (!this.hf) return
    const { rows, cols } = this.state
    const data = []
    for (let r = 0; r < rows; r++) {
      const row = []
      for (let c = 0; c < cols; c++) {
        const ref = this.cellRef(c, r)
        const cell = this.state.cells.get(ref)
        row.push(cell ? cell.raw : null)
      }
      data.push(row)
    }
    this.hf.setSheetContent(this.hfSheetIndex, data)
  }

  syncCellToHF(ref) {
    if (!this.hf) return
    const p = this.parseRef(ref)
    if (!p) return
    const cell = this.state.cells.get(ref)
    this.hf.setCellContents(
      { sheet: this.hfSheetIndex, row: p.r, col: p.c },
      cell ? cell.raw : null
    )
  }

  cellMouseDown(e) {
    e.preventDefault()
    const ref = e.currentTarget.dataset.ref
    this.state.selection = { anchor: ref, focus: ref }
    this._dragging = true
    this.renderGrid()
    const onEnter = (ev) => {
      const r = ev.target?.dataset?.ref
      if (this._dragging && r) { this.state.selection.focus = r; this.renderGrid() }
    }
    const onUp = () => {
      this._dragging = false
      this.gridTarget.removeEventListener("mouseover", onEnter)
      window.removeEventListener("mouseup", onUp)
    }
    this.gridTarget.addEventListener("mouseover", onEnter)
    window.addEventListener("mouseup", onUp)
  }

  selectionCells() {
    const a = this.parseRef(this.state.selection.anchor)
    const f = this.parseRef(this.state.selection.focus)
    if (!a || !f) return []
    const c1 = Math.min(a.c, f.c), c2 = Math.max(a.c, f.c)
    const r1 = Math.min(a.r, f.r), r2 = Math.max(a.r, f.r)
    const out = []
    for (let c = c1; c <= c2; c++)
      for (let r = r1; r <= r2; r++)
        out.push(this.cellRef(c, r))
    return out
  }

  editCell(e) {
    const ref = e.currentTarget.dataset.ref
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    const td = e.currentTarget
    td.innerHTML = `<input class="napkin-cell-input" value="${this.escape(cell.raw)}">`
    const input = td.querySelector("input")
    input.focus()
    input.select()
    const commit = () => {
      const newRaw = input.value
      this.setCell(ref, { ...cell, raw: newRaw })
      this.renderGrid()
    }
    input.addEventListener("blur", commit)
    input.addEventListener("keydown", (kev) => {
      if (kev.key === "Enter") { commit(); }
      if (kev.key === "Escape") { this.renderGrid(); }
    })
  }

  setCell(ref, cell) {
    if (!cell.raw && !cell.fmt) this.state.cells.delete(ref)
    else this.state.cells.set(ref, cell)
    this.syncCellToHF(ref)
    this.syncHiddenInput()
  }

  syncHiddenInput() {
    const cells = Object.fromEntries(this.state.cells)
    const hasAny = Object.keys(cells).length > 0
    this.hiddenInputTarget.value = hasAny
      ? JSON.stringify({ rows: this.state.rows, cols: this.state.cols, cells })
      : ""
  }

  isSelected(ref) {
    const a = this.parseRef(this.state.selection.anchor)
    const f = this.parseRef(this.state.selection.focus)
    const p = this.parseRef(ref)
    if (!a || !f || !p) return false
    const c1 = Math.min(a.c, f.c), c2 = Math.max(a.c, f.c)
    const r1 = Math.min(a.r, f.r), r2 = Math.max(a.r, f.r)
    return p.c >= c1 && p.c <= c2 && p.r >= r1 && p.r <= r2
  }

  updateFormulaBar() {
    if (!this.hasFormulaBarTarget) return
    const ref = this.state.selection.focus
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    this.formulaRefTarget.textContent = ref
    this.formulaBarTarget.value = cell.raw
  }

  formulaBarEdit() {
    const ref = this.state.selection.focus
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    this.setCell(ref, { ...cell, raw: this.formulaBarTarget.value })
    this.renderGrid()
  }

  formulaBarKey() {} // no-op for now

  applyFormat() {
    const style = this.fmtSelectTarget.value
    const dec = parseInt(this.decimalsInputTarget.value, 10) || 0
    let fmtStyle = ""
    if (style === "number") fmtStyle = `number:${dec}`
    else if (style.startsWith("currency:")) fmtStyle = `${style}:${dec}`
    else if (style === "percent") fmtStyle = `percent:${dec}`

    this.selectionCells().forEach((ref) => {
      const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
      const bold = (cell.fmt || "").split("|").includes("bold")
      const merged = [bold ? "bold" : null, fmtStyle || null].filter(Boolean).join("|")
      this.setCell(ref, { ...cell, fmt: merged || null })
    })
    this.renderGrid()
  }

  toggleBold() {
    this.selectionCells().forEach((ref) => {
      const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
      const parts = new Set((cell.fmt || "").split("|").filter(Boolean))
      parts.has("bold") ? parts.delete("bold") : parts.add("bold")
      this.setCell(ref, { ...cell, fmt: parts.size ? [...parts].join("|") : null })
    })
    this.renderGrid()
  }
  addRow() {
    if (this.state.rows >= 100) return
    this.state.rows += 1
    this.syncAllCellsToHF()
    this.renderGrid()
    this.syncHiddenInput()
  }

  addCol() {
    if (this.state.cols >= 26) return
    this.state.cols += 1
    this.syncAllCellsToHF()
    this.renderGrid()
    this.syncHiddenInput()
  }

  async ensureParserLoaded() {
    if (this.hf || this.parserLoading) return
    this.parserLoading = true
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
    try {
      const mod = await import("hyperformula")
      const HyperFormula = mod.HyperFormula || mod.default?.HyperFormula || mod.default
      this.hf = HyperFormula.buildEmpty({ licenseKey: "gpl-v3" })
      this.hfSheetId = this.hf.addSheet("napkin")
      this.hfSheetIndex = this.hf.getSheetId(this.hfSheetId)
      this.syncAllCellsToHF()
      this.renderGrid()
    } finally {
      this.parserLoading = false
      if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
    }
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[m])
  }
}
