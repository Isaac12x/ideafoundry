// Comparison bench instruments: Compare (side-by-side table) and Plot
// (periodicity and property-vs-property scatter, inline SVG).

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

function on(panel, type, selector, fn) {
  const handler = (e) => {
    const target = e.target.closest(selector)
    if (target && panel.contains(target)) fn(e, target)
  }
  panel.addEventListener(type, handler)
  return () => panel.removeEventListener(type, handler)
}

const COMPARE_SETS = [["Fe", "Co", "Ni"], ["Cu", "Ag", "Au"], ["Li", "Na", "K", "Rb", "Cs"], ["C", "Si", "Ge", "Sn", "Pb"], ["Ti", "Zr", "Hf"], ["Nb", "Ta"], ["F", "Cl", "Br", "I"], ["W", "Mo", "Cr"]]

const CATEGORICAL = [
  ["Series", (el, ctx) => ctx.categories?.[el.category]?.label ?? el.category],
  ["Block · group · period", (el) => `${el.block} · ${el.group ?? "—"} · ${el.period}`],
  ["Configuration", (el) => (el.electronConfig || "").replace(/^\*/, "")],
  ["Term symbol", (el) => el.groundLevel],
  ["Main oxidation states", (el) => (el.oxidationMain || []).map((s) => (s > 0 ? `+${s}` : s)).join(", ")],
  ["Crystal structure", (el, ctx) => ctx.trends.LENSES.crystal.classes[el.latticeStructure]?.label ?? el.latticeStructure],
  ["Magnetism", (el, ctx) => ctx.trends.LENSES.magnetic.classes[el.magnetic?.ordering]?.label],
  ["Goldschmidt class", (el) => el.goldschmidt],
  ["Biological role", (el, ctx) => ctx.trends.LENSES.bio.classes[el.bio?.role]?.label],
  ["Discovered", (el) => (el.ancient ? "antiquity" : el.yearDiscovered)]
]

// ── Compare ───────────────────────────────────────────────────────────
export function mountCompare(panel, initialCtx) {
  let ctx = initialCtx
  const scales = {}

  const render = async () => {
    const { trends, elements } = ctx
    if (!ctx.categories) ctx.categories = (await import("lib/periodic_table/elements")).CATEGORIES
    const list = ctx.tray.map((s) => ctx.bySymbol.get(s)).filter(Boolean).slice(0, 8)
    if (list.length < 2) {
      panel.innerHTML = `
        <div class="pb-empty">
          <h3 class="pb-title">Compare elements side by side</h3>
          <p>Put two to eight elements in the tray. Each bar shows where the value sits across all 118 elements; the best value in each row is marked.</p>
          <div class="pb-examples">${COMPARE_SETS.map((set) => `<button type="button" class="pb-example" data-set="${set.join(" ")}">${set.join(" · ")}</button>`).join("")}</div>
        </div>`
      return
    }
    const head = `<tr><th></th>${list.map((el) => `<th><button type="button" class="pb-compare-head" data-open="${el.number}" data-category="${el.category}"><b>${el.symbol}</b><small>${esc(el.name)}</small></button></th>`).join("")}</tr>`
    const groups = trends.PROPERTY_GROUPS.map((group) => {
      const rows = Object.entries(trends.PROPERTIES)
        .filter(([, p]) => p.group === group)
        .map(([key, p]) => {
          const acc = trends.propertyAccessor(key)
          const vals = list.map(acc)
          if (vals.every((v) => v == null)) return ""
          scales[key] ??= trends.scale(elements, key, { log: !!p.log })
          const finite = vals.filter((v) => v != null)
          const max = Math.max(...finite)
          const min = Math.min(...finite)
          return `<tr><th scope="row" title="${esc(p.trend)}">${esc(p.label)}${p.unit ? ` <small>${esc(p.unit)}</small>` : ""}</th>${vals.map((v) => {
            const n = scales[key].norm(v)
            const mark = finite.length > 1 && v != null ? (v === max ? " is-max" : v === min ? " is-min" : "") : ""
            return `<td class="pb-cmp${mark}">${v == null ? "—" : `<span class="pb-cmp-val">${trends.formatValue(v)}</span><span class="pb-cmp-bar"><span style="width:${((n ?? 0) * 100).toFixed(1)}%"></span></span>`}</td>`
          }).join("")}</tr>`
        }).join("")
      return rows ? `<tbody><tr class="pb-group-row"><th colspan="${list.length + 1}">${esc(group)}</th></tr>${rows}</tbody>` : ""
    }).join("")
    const cats = `<tbody><tr class="pb-group-row"><th colspan="${list.length + 1}">Identity</th></tr>${CATEGORICAL.map(([label, f]) => `<tr><th scope="row">${label}</th>${list.map((el) => `<td>${esc(f(el, ctx) ?? "—")}</td>`).join("")}</tr>`).join("")}</tbody>`
    panel.innerHTML = `
      <div class="pb-card pb-card--flush">
        <div class="pb-table-wrap pb-table-wrap--compare"><table class="pb-table pb-table--compare"><thead>${head}</thead>${cats}${groups}</table></div>
        <p class="pb-note">Bars place each value on the full-table range (log scale where the property spans orders of magnitude). ▲ highest / ▼ lowest among the compared elements. Hover a property name for what its trend means.</p>
      </div>`
  }

  const offs = [
    on(panel, "click", "[data-set]", (_e, b) => ctx.setTray(b.dataset.set.split(" "))),
    on(panel, "click", "[data-open]", (_e, b) => ctx.openElement(Number(b.dataset.open)))
  ]
  render()
  return {
    update(next) { ctx = next; render() },
    destroy() { offs.forEach((off) => off()) }
  }
}

// ── Plot ──────────────────────────────────────────────────────────────
const W = 860
const H = 440
const M = { top: 18, right: 22, bottom: 46, left: 64 }

function niceTicks(min, max, count = 6) {
  const span = max - min || 1
  const step0 = span / count
  const mag = 10 ** Math.floor(Math.log10(step0))
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= step0) || mag * 10
  const ticks = []
  for (let v = Math.ceil(min / step) * step; v <= max + step * 1e-9; v += step) ticks.push(Number(v.toPrecision(12)))
  return ticks
}

function logTicks(min, max) {
  const out = []
  for (let e = Math.floor(Math.log10(min)); e <= Math.ceil(Math.log10(max)); e++) {
    const v = 10 ** e
    if (v >= min * 0.999 && v <= max * 1.001) out.push(v)
  }
  return out
}

const PRESETS = [
  ["ionization1", null, "Ionisation energy vs Z — the signature of shells"],
  ["atomicRadius", null, "Atomic radius vs Z"],
  ["molarVolume", null, "Lothar Meyer's atomic-volume curve"],
  ["melt", null, "Melting point vs Z"],
  ["atomicRadius", "ionization1", "Size vs ionisation energy"],
  ["electronegativity", "ionization1", "χ vs ionisation energy"],
  ["density", "youngsModulus", "Ashby-style: stiffness vs density"],
  ["melt", "youngsModulus", "Stiffness tracks melting point"],
  ["abundanceCrust", "pricePerKg", "Scarcity vs price"]
]

export function mountPlot(panel, initialCtx) {
  let ctx = initialCtx
  let yKey = "ionization1"
  let xKey = null // null = atomic number
  let yLog = false
  let xLog = false
  let colorBy = "category"

  const propOptions = (selected, allowZ) => {
    const { PROPERTIES, PROPERTY_GROUPS } = ctx.trends
    return (allowZ ? `<option value="" ${selected == null ? "selected" : ""}>Atomic number (Z)</option>` : "") +
      PROPERTY_GROUPS.map((g) => `<optgroup label="${esc(g)}">${Object.entries(PROPERTIES).filter(([, p]) => p.group === g).map(([k, p]) => `<option value="${k}" ${k === selected ? "selected" : ""}>${esc(p.label)}</option>`).join("")}</optgroup>`).join("")
  }

  panel.innerHTML = `
    <div class="pb-plot">
      <div class="pb-plot-controls">
        <label class="pb-field"><span>Y axis</span><select data-in="y"></select></label>
        <label class="pb-check"><input type="checkbox" data-in="ylog"> log</label>
        <label class="pb-field"><span>X axis</span><select data-in="x"></select></label>
        <label class="pb-check"><input type="checkbox" data-in="xlog"> log</label>
        <label class="pb-field"><span>Colour</span><select data-in="color"><option value="category">Series</option><option value="block">Block</option><option value="period">Period</option></select></label>
      </div>
      <div class="pb-examples pb-examples--presets">${PRESETS.map(([, , label], i) => `<button type="button" class="pb-example" data-preset="${i}">${esc(label)}</button>`).join("")}</div>
      <figure class="pb-plot-figure">
        <svg viewBox="0 0 ${W} ${H}" class="pb-plot-svg" role="img" data-out="svg"></svg>
        <div class="pb-plot-tip" data-out="tip" hidden></div>
      </figure>
      <p class="pb-note" data-out="caption"></p>
    </div>`

  const $ = (sel) => panel.querySelector(sel)

  const colorOf = (el) => {
    if (colorBy === "block") return ctx.trends.LENSES.block.classes[el.block]?.color
    if (colorBy === "period") return `oklch(72% 0.11 ${(el.period * 47) % 360})`
    return `var(--cat-${el.category})`
  }

  const draw = () => {
    const { trends, elements } = ctx
    $('[data-in="y"]').innerHTML = propOptions(yKey, false)
    $('[data-in="x"]').innerHTML = propOptions(xKey, true)
    $('[data-in="ylog"]').checked = yLog
    $('[data-in="xlog"]').checked = xLog
    $('[data-in="color"]').value = colorBy
    const yAcc = trends.propertyAccessor(yKey)
    const xAcc = xKey ? trends.propertyAccessor(xKey) : (el) => el.number
    const pts = elements
      .map((el) => ({ el, x: xAcc(el), y: yAcc(el) }))
      .filter((p) => p.x != null && p.y != null && Number.isFinite(p.x) && Number.isFinite(p.y) && (!yLog || p.y > 0) && (!xLog || p.x > 0))
    const svg = $('[data-out="svg"]')
    if (pts.length < 2) {
      svg.innerHTML = `<text x="${W / 2}" y="${H / 2}" text-anchor="middle" class="pb-axis-label">Not enough data for this combination</text>`
      return
    }
    const xs = pts.map((p) => p.x)
    const ys = pts.map((p) => p.y)
    let [x0, x1] = [Math.min(...xs), Math.max(...xs)]
    let [y0, y1] = [Math.min(...ys), Math.max(...ys)]
    if (!xLog) { const pad = (x1 - x0) * 0.03 || 1; x0 -= pad; x1 += pad }
    if (!yLog) { const pad = (y1 - y0) * 0.06 || 1; y0 = y0 >= 0 && y0 - pad < 0 ? 0 : y0 - pad; y1 += pad }
    const tx = (v) => (xLog ? Math.log10(v) : v)
    const ty = (v) => (yLog ? Math.log10(v) : v)
    const sx = (v) => M.left + ((tx(v) - tx(x0)) / (tx(x1) - tx(x0) || 1)) * (W - M.left - M.right)
    const sy = (v) => H - M.bottom - ((ty(v) - ty(y0)) / (ty(y1) - ty(y0) || 1)) * (H - M.top - M.bottom)
    const fmt = (v) => trends.formatValue(v)
    const xTicks = xLog ? logTicks(x0, x1) : niceTicks(x0, x1, 10)
    const yTicks = yLog ? logTicks(y0, y1) : niceTicks(y0, y1, 6)
    const tray = new Set(ctx.tray)
    const yMeta = trends.PROPERTIES[yKey]
    const xMeta = xKey ? trends.PROPERTIES[xKey] : { label: "Atomic number Z", unit: "" }

    // Noble gases close each period — guides make periodicity visible.
    const guides = !xKey ? elements.filter((el) => el.group === 18).map((el) => `<line class="pb-period-line" x1="${sx(el.number)}" x2="${sx(el.number)}" y1="${M.top}" y2="${H - M.bottom}"/><text class="pb-period-label" x="${sx(el.number) - 3}" y="${M.top + 10}" text-anchor="end">${el.symbol}</text>`).join("") : ""
    const line = !xKey ? `<path class="pb-line" d="${pts.map((p, i) => `${i && pts[i - 1].el.number === p.el.number - 1 ? "L" : "M"}${sx(p.x).toFixed(1)} ${sy(p.y).toFixed(1)}`).join("")}"/>` : ""
    const dots = pts.map((p) => {
      const inTray = tray.has(p.el.symbol)
      return `<g class="pb-dot${inTray ? " is-tray" : ""}" data-n="${p.el.number}" transform="translate(${sx(p.x).toFixed(1)} ${sy(p.y).toFixed(1)})"><circle r="${inTray ? 5.5 : 3.6}" style="fill:${colorOf(p.el)}"/>${inTray || (xKey && pts.length < 60) ? `<text x="7" y="4">${p.el.symbol}</text>` : ""}</g>`
    }).join("")
    const sorted = [...pts].sort((a, b) => b.y - a.y)
    const extremes = [...sorted.slice(0, 3), ...sorted.slice(-2)].filter((p) => !tray.has(p.el.symbol))
      .map((p) => `<text class="pb-extreme" x="${sx(p.x) + 6}" y="${sy(p.y) - 6}">${p.el.symbol}</text>`).join("")

    svg.setAttribute("aria-label", `${yMeta.label} against ${xMeta.label}`)
    svg.innerHTML = `
      <g class="pb-grid-lines">${yTicks.map((t) => `<line x1="${M.left}" x2="${W - M.right}" y1="${sy(t)}" y2="${sy(t)}"/>`).join("")}</g>
      ${guides}
      <g class="pb-axis">
        <line x1="${M.left}" x2="${W - M.right}" y1="${H - M.bottom}" y2="${H - M.bottom}"/>
        ${xTicks.map((t) => `<text x="${sx(t)}" y="${H - M.bottom + 16}" text-anchor="middle">${fmt(t)}</text>`).join("")}
        ${yTicks.map((t) => `<text x="${M.left - 8}" y="${sy(t) + 4}" text-anchor="end">${fmt(t)}</text>`).join("")}
        <text class="pb-axis-label" x="${(W + M.left) / 2}" y="${H - 8}" text-anchor="middle">${esc(xMeta.label)}${xMeta.unit ? ` (${esc(xMeta.unit)})` : ""}${xLog ? " · log" : ""}</text>
        <text class="pb-axis-label" transform="translate(16 ${(H - M.bottom + M.top) / 2}) rotate(-90)" text-anchor="middle">${esc(yMeta.label)}${yMeta.unit ? ` (${esc(yMeta.unit)})` : ""}${yLog ? " · log" : ""}</text>
      </g>
      ${line}${extremes}<g class="pb-dots">${dots}</g>`

    let caption = yMeta.trend || ""
    if (xKey) {
      const n = pts.length
      const mx = xs.reduce((a, b) => a + tx(b), 0) / n
      const my = ys.reduce((a, b) => a + ty(b), 0) / n
      let sxy = 0, sxx = 0, syy = 0
      pts.forEach((p) => { const dx = tx(p.x) - mx; const dy = ty(p.y) - my; sxy += dx * dy; sxx += dx * dx; syy += dy * dy })
      const r = sxy / Math.sqrt(sxx * syy || 1)
      caption = `${n} elements · Pearson r = ${r.toFixed(2)}${xLog || yLog ? " (on the log-transformed axes)" : ""}. ${Math.abs(r) > 0.7 ? "Strong correlation — the two properties share a physical origin." : Math.abs(r) > 0.4 ? "Moderate correlation." : "Weak correlation — other factors dominate."}`
    }
    $('[data-out="caption"]').textContent = `${caption} Click a point to open the element; tray elements are enlarged and labelled.`
  }

  const tip = () => $('[data-out="tip"]')
  const offs = [
    on(panel, "change", "[data-in]", (_e, input) => {
      const k = input.dataset.in
      if (k === "y") { yKey = input.value; yLog = !!ctx.trends.PROPERTIES[yKey]?.log }
      if (k === "x") { xKey = input.value || null; xLog = xKey ? !!ctx.trends.PROPERTIES[xKey]?.log : false }
      if (k === "ylog") yLog = input.checked
      if (k === "xlog") xLog = input.checked
      if (k === "color") colorBy = input.value
      draw()
    }),
    on(panel, "click", "[data-preset]", (_e, b) => {
      const [y, x] = PRESETS[Number(b.dataset.preset)]
      yKey = y
      xKey = x
      yLog = !!ctx.trends.PROPERTIES[y]?.log
      xLog = x ? !!ctx.trends.PROPERTIES[x]?.log : false
      draw()
    }),
    on(panel, "mouseover", ".pb-dot", (_e, g) => {
      const el = ctx.elements[Number(g.dataset.n) - 1]
      const { trends } = ctx
      const y = trends.propertyAccessor(yKey)(el)
      const x = xKey ? trends.propertyAccessor(xKey)(el) : el.number
      const t = tip()
      t.hidden = false
      t.innerHTML = `<b>${el.symbol}</b> ${esc(el.name)}<br>${esc(trends.PROPERTIES[yKey].label)}: ${trends.formatValue(y, trends.PROPERTIES[yKey].unit)}<br>${xKey ? `${esc(trends.PROPERTIES[xKey].label)}: ${trends.formatValue(x, trends.PROPERTIES[xKey].unit)}` : `Z = ${el.number}`}`
      const box = panel.querySelector(".pb-plot-figure").getBoundingClientRect()
      const r = g.getBoundingClientRect()
      t.style.left = `${Math.min(box.width - 180, r.left - box.left + 10)}px`
      t.style.top = `${r.top - box.top - 10}px`
    }),
    on(panel, "mouseout", ".pb-dot", () => { tip().hidden = true }),
    on(panel, "click", ".pb-dot", (_e, g) => ctx.openElement(Number(g.dataset.n)))
  ]

  draw()
  return {
    update(next) { ctx = next; draw() },
    focus(opts = {}) {
      if (opts.property && ctx.trends.PROPERTIES[opts.property]) {
        yKey = opts.property
        xKey = null
        yLog = !!ctx.trends.PROPERTIES[yKey].log
        xLog = false
        draw()
      }
    },
    destroy() { offs.forEach((off) => off()) }
  }
}
