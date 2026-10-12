// Chart of nuclides (Segrè chart) + binding-energy curve, drawn on canvas.
// Data: nuclides.mjs rows [Z, N, t½ s (-1 stable), mode, abundance %, Jπ, B/A keV, discovery year].

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
const MAGIC = [2, 8, 20, 28, 50, 82, 126]

const MODE_GROUPS = {
  stable: { label: "Stable", color: "#1d1b22", test: (r) => r[2] === -1 },
  "B-": { label: "β⁻ decay", color: "#5b8fd9", test: (r) => /^2?B-/.test(r[3] || "") },
  "B+": { label: "β⁺ / electron capture", color: "#e07062", test: (r) => /^(EC|B\+|2EC|2B\+)/.test(r[3] || "") },
  A: { label: "α decay", color: "#e3c457", test: (r) => r[3] === "A" },
  SF: { label: "Spontaneous fission", color: "#6cbf84", test: (r) => r[3] === "SF" },
  P: { label: "Proton emission", color: "#e39a52", test: (r) => /^2?P$/.test(r[3] || "") },
  N: { label: "Neutron emission", color: "#a585d6", test: (r) => /^2?N$/.test(r[3] || "") },
  other: { label: "Other / unknown", color: "#6b6872", test: () => true }
}

function modeKey(r) {
  for (const [k, g] of Object.entries(MODE_GROUPS)) if (g.test(r)) return k
  return "other"
}

export function humanHalfLife(sec) {
  if (sec == null) return "unknown"
  if (sec === -1) return "stable"
  const y = 365.2422 * 86400
  const units = [[y * 1e9, "Gy"], [y * 1e6, "My"], [y * 1e3, "ky"], [y, "y"], [86400, "d"], [3600, "h"], [60, "min"], [1, "s"], [1e-3, "ms"], [1e-6, "µs"], [1e-9, "ns"], [1e-12, "ps"], [1e-15, "fs"], [1e-18, "as"], [1e-21, "zs"]]
  for (const [f, u] of units) if (sec >= f) return `${Number((sec / f).toPrecision(3))} ${u}`
  return `${Number((sec / 1e-24).toPrecision(3))} ys`
}

// Perceptual-ish ramp (deep violet → teal → amber → bone) for continuous metrics.
function ramp(t) {
  const stops = [[38, 0.09, 290], [55, 0.11, 230], [68, 0.12, 170], [78, 0.13, 95], [92, 0.05, 85]]
  const x = Math.min(0.9999, Math.max(0, t)) * (stops.length - 1)
  const i = Math.floor(x)
  const f = x - i
  const [l1, c1, h1] = stops[i]
  const [l2, c2, h2] = stops[i + 1]
  return `oklch(${l1 + (l2 - l1) * f}% ${c1 + (c2 - c1) * f} ${h1 + (h2 - h1) * f})`
}

export function mountNuclides(panel, initialCtx) {
  let ctx = initialCtx
  let rows = null
  let colorBy = "mode"
  let focusZ = null
  let view = { scale: 1, ox: 0, oy: 0 }
  let drag = null
  let hover = null
  let pendingZ = null
  const byZ = new Map()

  panel.innerHTML = `
    <div class="pb-nuclides">
      <div class="pb-plot-controls">
        <label class="pb-field"><span>Colour by</span>
          <select data-in="color">
            <option value="mode">Decay mode</option>
            <option value="halflife">Half-life (log)</option>
            <option value="binding">Binding energy per nucleon</option>
            <option value="year">Year discovered</option>
          </select></label>
        <label class="pb-field"><span>Go to element</span><input type="text" data-in="goto" placeholder="e.g. U or 92" autocomplete="off" spellcheck="false"></label>
        <div class="pb-seg" role="group" aria-label="Zoom">
          <button type="button" data-zoom="in" aria-label="Zoom in">+</button>
          <button type="button" data-zoom="out" aria-label="Zoom out">−</button>
          <button type="button" data-zoom="reset">Fit</button>
        </div>
      </div>
      <figure class="pb-nuc-figure">
        <canvas class="pb-nuc-canvas" data-out="canvas" tabindex="0" role="img" aria-label="Chart of nuclides: proton number Z against neutron number N"></canvas>
        <div class="pb-plot-tip" data-out="tip" hidden></div>
      </figure>
      <div class="pb-nuc-foot">
        <div class="pb-nuc-legend" data-out="legend"></div>
        <p class="pb-note">Each square is one nuclide: protons (Z) up, neutrons (N) across. The black <b>valley of stability</b> bends below N = Z because extra neutrons dilute proton repulsion. Lines mark magic numbers (2, 8, 20, 28, 50, 82, 126) where closed nuclear shells add stability. Scroll to zoom, drag to pan, click to open the element.</p>
      </div>
      <section class="pb-card">
        <h3 class="pb-title">Binding energy per nucleon</h3>
        <canvas class="pb-be-canvas" data-out="be" role="img" aria-label="Binding energy per nucleon against mass number"></canvas>
        <p class="pb-note">The curve peaks near ⁵⁶Fe/⁶²Ni (~8.8 MeV per nucleon). Fusing light nuclei or splitting heavy ones both climb toward that peak — the energy source of stars and of reactors. Stars cannot fuse past iron for energy.</p>
      </section>
    </div>`

  const $ = (sel) => panel.querySelector(sel)
  const canvas = $('[data-out="canvas"]')
  const cctx = canvas.getContext("2d")
  let maxN = 0
  let maxZ = 0
  let ranges = {}

  const fitView = () => {
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    const cell = Math.min((w - 40) / (maxN + 2), (h - 30) / (maxZ + 2))
    view = { scale: cell, ox: 30, oy: h - 22 }
  }

  const resize = () => {
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    // Z:N spans ~118:177 — match that aspect so the chart fills the width.
    const h = Math.max(380, Math.min(880, w * 0.7))
    canvas.style.height = `${h}px`
    canvas.width = Math.round(w * dpr)
    canvas.height = Math.round(h * dpr)
    cctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }

  const colorFor = (r) => {
    if (colorBy === "mode") return MODE_GROUPS[modeKey(r)].color
    if (colorBy === "halflife") {
      if (r[2] === -1) return "#1d1b22"
      if (r[2] == null || r[2] <= 0) return "#3a3840"
      return ramp((Math.log10(r[2]) - ranges.hl[0]) / (ranges.hl[1] - ranges.hl[0]))
    }
    if (colorBy === "binding") return r[6] == null ? "#3a3840" : ramp((r[6] - ranges.be[0]) / (ranges.be[1] - ranges.be[0]))
    if (colorBy === "year") return r[7] == null ? "#3a3840" : ramp((r[7] - ranges.yr[0]) / (ranges.yr[1] - ranges.yr[0]))
    return "#888"
  }

  const toScreen = (n, z) => [view.ox + n * view.scale, view.oy - (z + 1) * view.scale]
  const fromScreen = (x, y) => [Math.floor((x - view.ox) / view.scale), Math.floor((view.oy - y) / view.scale)]

  const draw = () => {
    if (!rows) return
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    const s = view.scale
    const styles = getComputedStyle(panel)
    const ink = styles.getPropertyValue("--text-secondary").trim() || "#9a9498"
    const faint = styles.getPropertyValue("--border-default").trim() || "#2a2a36"
    cctx.clearRect(0, 0, w, h)

    // magic-number bands
    cctx.strokeStyle = faint
    cctx.lineWidth = 1
    cctx.font = "10px JetBrains Mono, monospace"
    cctx.fillStyle = ink
    for (const m of MAGIC) {
      const [xn] = toScreen(m, 0)
      const [, yz] = toScreen(0, m)
      if (m <= maxN) { cctx.beginPath(); cctx.moveTo(xn, 0); cctx.lineTo(xn, h - 18); cctx.stroke(); cctx.fillText(`N=${m}`, xn + 2, h - 6) }
      if (m <= maxZ) { cctx.beginPath(); cctx.moveTo(24, yz); cctx.lineTo(w, yz); cctx.stroke(); cctx.fillText(`${m}`, 2, yz + 4) }
    }
    // N = Z
    cctx.setLineDash([4, 4])
    const [ax, ay] = toScreen(0, -1)
    const [bx, by] = toScreen(maxZ, maxZ - 1)
    cctx.beginPath(); cctx.moveTo(ax, ay); cctx.lineTo(bx, by); cctx.stroke()
    cctx.setLineDash([])

    const gap = s > 6 ? 1 : 0
    for (const r of rows) {
      const [x, y] = toScreen(r[1], r[0])
      if (x < -s || y < -s || x > w || y > h) continue
      cctx.fillStyle = colorFor(r)
      cctx.fillRect(x, y, Math.max(1, s - gap), Math.max(1, s - gap))
      if (r[2] === -1 && colorBy !== "mode" && s > 4) {
        cctx.strokeStyle = "#ece8e1"
        cctx.strokeRect(x + 0.5, y + 0.5, s - gap - 1, s - gap - 1)
      }
    }
    // element labels when zoomed in
    if (s >= 14) {
      cctx.font = `${Math.min(12, s * 0.42)}px Outfit, sans-serif`
      cctx.textAlign = "center"
      for (const r of rows) {
        const [x, y] = toScreen(r[1], r[0])
        if (x < -s || y < -s || x > w || y > h) continue
        const el = ctx.elements[r[0] - 1]
        cctx.fillStyle = r[2] === -1 && colorBy === "mode" ? "#ece8e1" : "#14141a"
        cctx.fillText(`${r[0] + r[1]}${el?.symbol ?? ""}`, x + s / 2, y + s / 2 + 4)
      }
      cctx.textAlign = "start"
    }
    // focus row
    if (focusZ != null) {
      const list = byZ.get(focusZ) || []
      if (list.length) {
        const [x0, y0] = toScreen(list[0][1], focusZ)
        const [x1] = toScreen(list[list.length - 1][1], focusZ)
        cctx.strokeStyle = "#d4953a"
        cctx.lineWidth = 2
        cctx.strokeRect(x0 - 2, y0 - 2, x1 - x0 + s + 4, s + 4)
        cctx.lineWidth = 1
      }
    }
    if (hover) {
      const [x, y] = toScreen(hover[1], hover[0])
      cctx.strokeStyle = "#ece8e1"
      cctx.lineWidth = 2
      cctx.strokeRect(x - 1, y - 1, s + 1, s + 1)
      cctx.lineWidth = 1
    }
    cctx.fillStyle = ink
    cctx.font = "11px Outfit, sans-serif"
    cctx.fillText("Z ↑ protons", 30, 12)
    cctx.fillText("N → neutrons", w - 90, h - 6)
  }

  const legend = () => {
    const out = $('[data-out="legend"]')
    if (colorBy === "mode") {
      const counts = {}
      rows.forEach((r) => { const k = modeKey(r); counts[k] = (counts[k] || 0) + 1 })
      out.innerHTML = Object.entries(MODE_GROUPS).map(([k, g]) => `<span class="pb-key"><i style="background:${g.color}"></i>${g.label} <small>${counts[k] || 0}</small></span>`).join("")
    } else {
      const lab = { halflife: ["< 1 µs", "> 1 Gy"], binding: [`${(ranges.be[0] / 1000).toFixed(1)} MeV`, `${(ranges.be[1] / 1000).toFixed(2)} MeV`], year: [String(ranges.yr[0]), String(ranges.yr[1])] }[colorBy]
      out.innerHTML = `<span class="pb-key">${lab[0]}</span><span class="pb-ramp" style="background:linear-gradient(90deg, ${[0, 0.25, 0.5, 0.75, 1].map(ramp).join(",")})"></span><span class="pb-key">${lab[1]}</span>${colorBy === "halflife" ? `<span class="pb-key"><i style="background:#1d1b22;outline:1px solid #ece8e1"></i>stable</span>` : ""}`
    }
  }

  const drawBinding = () => {
    const c = $('[data-out="be"]')
    const dpr = window.devicePixelRatio || 1
    const w = c.clientWidth
    const h = 220
    c.style.height = `${h}px`
    c.width = w * dpr
    c.height = h * dpr
    const g = c.getContext("2d")
    g.setTransform(dpr, 0, 0, dpr, 0, 0)
    // most stable (or longest-lived) nuclide per mass number A
    const bestByA = new Map()
    for (const r of rows) {
      if (r[6] == null) continue
      const A = r[0] + r[1]
      const cur = bestByA.get(A)
      const life = r[2] === -1 ? Infinity : r[2] ?? 0
      if (!cur || life > cur.life) bestByA.set(A, { r, life })
    }
    const pts = [...bestByA.entries()].sort((a, b) => a[0] - b[0]).map(([A, { r }]) => [A, r[6] / 1000, r])
    const maxA = pts[pts.length - 1][0]
    const L = 40, B = 24, T = 10
    const sx = (A) => L + (A / maxA) * (w - L - 10)
    const sy = (v) => h - B - (v / 9.2) * (h - B - T)
    const styles = getComputedStyle(panel)
    const ink = styles.getPropertyValue("--text-secondary").trim() || "#9a9498"
    g.strokeStyle = styles.getPropertyValue("--border-default").trim() || "#2a2a36"
    g.fillStyle = ink
    g.font = "10px JetBrains Mono, monospace"
    for (let v = 0; v <= 9; v += 1) { g.beginPath(); g.moveTo(L, sy(v)); g.lineTo(w - 10, sy(v)); g.stroke(); g.fillText(`${v}`, L - 14, sy(v) + 3) }
    for (let A = 0; A <= maxA; A += 50) g.fillText(`${A}`, sx(A) - 6, h - 8)
    g.strokeStyle = "#d4953a"
    g.lineWidth = 1.6
    g.beginPath()
    pts.forEach(([A, v], i) => (i ? g.lineTo(sx(A), sy(v)) : g.moveTo(sx(A), sy(v))))
    g.stroke()
    const peak = pts.reduce((a, b) => (b[1] > a[1] ? b : a))
    g.fillStyle = "#ece8e1"
    g.beginPath(); g.arc(sx(peak[0]), sy(peak[1]), 3.5, 0, Math.PI * 2); g.fill()
    const el = ctx.elements[peak[2][0] - 1]
    g.fillText(`${peak[0]}${el.symbol} ${peak[1].toFixed(3)} MeV`, sx(peak[0]) + 6, sy(peak[1]) - 6)
    for (const label of [[4, "⁴He"], [12, "¹²C"], [16, "¹⁶O"], [235, "²³⁵U"]]) {
      const p = pts.find(([A]) => A === label[0])
      if (p) { g.fillText(label[1], sx(p[0]) + 4, sy(p[1]) + 12) }
    }
    g.fillStyle = ink
    g.fillText("B/A (MeV)", 4, 10)
    g.fillText("mass number A", w - 100, h - 8)
  }

  const showTip = (r, x, y) => {
    const t = $('[data-out="tip"]')
    if (!r) { t.hidden = true; return }
    const el = ctx.elements[r[0] - 1]
    t.hidden = false
    t.innerHTML = `<b><sup>${r[0] + r[1]}</sup>${esc(el?.symbol ?? "")}</b> ${esc(el?.name ?? "")}<br>Z ${r[0]} · N ${r[1]}<br>${r[2] === -1 ? "stable" : `t½ ${humanHalfLife(r[2])}`}${r[3] ? ` · ${esc(r[3])}` : ""}${r[4] ? `<br>abundance ${r[4]}%` : ""}${r[5] ? `<br>Jπ ${esc(r[5])}` : ""}${r[6] != null ? `<br>B/A ${(r[6] / 1000).toFixed(3)} MeV` : ""}${r[7] ? `<br>discovered ${r[7]}` : ""}`
    const fig = panel.querySelector(".pb-nuc-figure").getBoundingClientRect()
    t.style.left = `${Math.min(fig.width - 190, x + 14)}px`
    t.style.top = `${Math.max(0, y - 10)}px`
  }

  const hit = (e) => {
    const rect = canvas.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top
    const [n, z] = fromScreen(x, y)
    return { x, y, r: (byZ.get(z) || []).find((r) => r[1] === n) || null }
  }

  const zoomAt = (factor, x, y) => {
    const ns = Math.min(60, Math.max(1.5, view.scale * factor))
    const f = ns / view.scale
    view = { scale: ns, ox: x - (x - view.ox) * f, oy: y - (y - view.oy) * f }
    draw()
  }

  const focusElement = (z) => {
    focusZ = z
    const list = byZ.get(z) || []
    if (list.length) {
      const mid = list[Math.floor(list.length / 2)]
      const scale = 18
      view = { scale, ox: canvas.clientWidth / 2 - mid[1] * scale, oy: canvas.clientHeight / 2 + (z + 0.5) * scale }
    }
    draw()
  }

  const listeners = []
  const add = (target, type, fn, opts) => { target.addEventListener(type, fn, opts); listeners.push([target, type, fn]) }

  add(canvas, "wheel", (e) => {
    e.preventDefault()
    const rect = canvas.getBoundingClientRect()
    zoomAt(e.deltaY < 0 ? 1.15 : 1 / 1.15, e.clientX - rect.left, e.clientY - rect.top)
  }, { passive: false })
  add(canvas, "pointerdown", (e) => { drag = { x: e.clientX, y: e.clientY, ox: view.ox, oy: view.oy, moved: false }; canvas.setPointerCapture(e.pointerId) })
  add(canvas, "pointermove", (e) => {
    if (drag) {
      const dx = e.clientX - drag.x
      const dy = e.clientY - drag.y
      if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true
      view.ox = drag.ox + dx
      view.oy = drag.oy + dy
      draw()
      return
    }
    const { x, y, r } = hit(e)
    if (r !== hover) { hover = r; draw() }
    showTip(r, x, y)
  })
  add(canvas, "pointerup", (e) => {
    const wasDrag = drag?.moved
    drag = null
    if (wasDrag) return
    const { r } = hit(e)
    if (r) ctx.openElement(r[0])
  })
  add(canvas, "pointerleave", () => { hover = null; showTip(null); draw() })
  add(canvas, "keydown", (e) => {
    const step = 40
    if (e.key === "+" || e.key === "=") zoomAt(1.25, canvas.clientWidth / 2, canvas.clientHeight / 2)
    else if (e.key === "-") zoomAt(0.8, canvas.clientWidth / 2, canvas.clientHeight / 2)
    else if (e.key === "ArrowLeft") { view.ox += step; draw() }
    else if (e.key === "ArrowRight") { view.ox -= step; draw() }
    else if (e.key === "ArrowUp") { view.oy += step; draw() }
    else if (e.key === "ArrowDown") { view.oy -= step; draw() }
    else return
    e.preventDefault()
  })
  const onPanelChange = (e) => {
    if (e.target.dataset.in === "color") { colorBy = e.target.value; draw(); legend() }
  }
  const onPanelClick = (e) => {
    const b = e.target.closest("[data-zoom]")
    if (!b) return
    const cx = canvas.clientWidth / 2
    const cy = canvas.clientHeight / 2
    if (b.dataset.zoom === "in") zoomAt(1.4, cx, cy)
    if (b.dataset.zoom === "out") zoomAt(1 / 1.4, cx, cy)
    if (b.dataset.zoom === "reset") { focusZ = null; fitView(); draw() }
  }
  const onGoto = (e) => {
    if (e.target.dataset.in !== "goto" || e.key !== "Enter") return
    const q = e.target.value.trim()
    const el = ctx.elements.find((x) => x.symbol.toLowerCase() === q.toLowerCase() || String(x.number) === q || x.name.toLowerCase() === q.toLowerCase())
    if (el) focusElement(el.number)
  }
  add(panel, "change", onPanelChange)
  add(panel, "click", onPanelClick)
  add(panel, "keydown", onGoto)

  const ro = new ResizeObserver(() => {
    if (!rows || !canvas.clientWidth) return
    resize()
    if (focusZ != null) focusElement(focusZ)
    else { fitView(); draw() }
    drawBinding()
  })

  import("lib/periodic_table/nuclides").then(({ NUCLIDES }) => {
    rows = NUCLIDES
    for (const r of rows) {
      maxN = Math.max(maxN, r[1])
      maxZ = Math.max(maxZ, r[0])
      if (!byZ.has(r[0])) byZ.set(r[0], [])
      byZ.get(r[0]).push(r)
    }
    byZ.forEach((list) => list.sort((a, b) => a[1] - b[1]))
    const be = rows.filter((r) => r[6] != null && r[0] + r[1] > 4).map((r) => r[6])
    const yr = rows.filter((r) => r[7]).map((r) => r[7])
    // half-life ramp spans log10(t½/s) from −9 (1 ns) to 17 (~3 Gy)
    ranges = { hl: [-9, 17], be: [Math.min(...be), Math.max(...be)], yr: [Math.min(...yr), Math.max(...yr)] }
    resize()
    fitView()
    draw()
    legend()
    drawBinding()
    ro.observe(canvas)
    if (pendingZ != null) focusElement(pendingZ)
  })

  return {
    update(next) { ctx = next },
    focus(opts = {}) {
      if (!opts.z) return
      if (rows) focusElement(opts.z)
      else pendingZ = opts.z
    },
    destroy() {
      ro.disconnect()
      listeners.forEach(([t, type, fn]) => t.removeEventListener(type, fn))
    }
  }
}
