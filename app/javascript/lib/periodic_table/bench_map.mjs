// Discovery map: where every element was first isolated, identified or
// synthesised (ancient elements: earliest known use). SVG, equirectangular.

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

const VIEWS = {
  world: [0, 0, 360, 150],
  europe: [166, 16, 60, 40],
  americas: [50, 20, 90, 80],
  asia: [215, 10, 140, 85]
}

const yearOf = (el) => (el.ancient ? el.earliestUse ?? -9000 : el.yearDiscovered)
const yearLabel = (y) => (y < 0 ? `${-y} BCE` : `${y}`)
const country = (place) => (place || "").split(/[,(]/).slice(-1)[0].replace(/\)$/, "").trim() || place

export function mountMap(panel, initialCtx) {
  let ctx = initialCtx
  let year = 2010
  let viewKey = "world"
  let selectedKey = null
  let timer = null
  const lens = ctx.trends.LENSES.discoveryMethod

  // Cluster by rounded coordinates (~0.5°).
  const clusters = new Map()
  for (const el of ctx.elements) {
    if (el.discoveryLat == null) continue
    const key = `${Math.round(el.discoveryLat * 2) / 2},${Math.round(el.discoveryLon * 2) / 2}`
    if (!clusters.has(key)) clusters.set(key, { key, lat: el.discoveryLat, lon: el.discoveryLon, elements: [] })
    clusters.get(key).elements.push(el)
  }
  clusters.forEach((c) => c.elements.sort((a, b) => yearOf(a) - yearOf(b)))
  const placeName = (c) => c.elements[c.elements.length - 1].discoveryPlace

  panel.innerHTML = `
    <div class="pb-map">
      <div class="pb-plot-controls">
        <button type="button" class="ptable-discovery-play" data-act="play" aria-label="Play timeline">▶</button>
        <input type="range" min="-9000" max="2010" value="2010" class="pb-map-slider" data-in="year" aria-label="Year">
        <output class="ptable-readout" data-out="year">2010</output>
        <div class="pb-seg" role="group" aria-label="Map region">
          ${Object.keys(VIEWS).map((k) => `<button type="button" data-view="${k}" aria-pressed="${k === viewKey}">${k[0].toUpperCase() + k.slice(1)}</button>`).join("")}
        </div>
      </div>
      <div class="pb-map-body">
        <figure class="pb-map-figure">
          <svg class="pb-map-svg" data-out="svg" viewBox="${VIEWS.world.join(" ")}" role="img" aria-label="World map of element discovery locations">
            <rect class="pb-sea" x="-10" y="-10" width="380" height="170"/>
            <g class="pb-graticule">${[-150, -120, -90, -60, -30, 0, 30, 60, 90, 120, 150].map((lon) => `<line x1="${lon + 180}" x2="${lon + 180}" y1="0" y2="150"/>`).join("")}${[60, 30, 0, -30].map((lat) => `<line x1="0" x2="360" y1="${90 - lat}" y2="${90 - lat}"/>`).join("")}</g>
            <path class="pb-land" data-out="land" d=""/>
            <g data-out="pins"></g>
          </svg>
          <div class="pb-plot-tip" data-out="tip" hidden></div>
        </figure>
        <aside class="pb-map-side" data-out="side"></aside>
      </div>
      <div class="pb-nuc-legend">${Object.entries(lens.classes).filter(([k]) => k !== "unknown").map(([, c]) => `<span class="pb-key"><i style="background:${c.color}"></i>${c.label}</span>`).join("")}<span class="pb-key"><i class="pb-key-ring"></i>ancient: earliest known use</span></div>
    </div>`

  const $ = (sel) => panel.querySelector(sel)
  const svg = $('[data-out="svg"]')

  const visible = (el) => yearOf(el) <= year

  const drawPins = () => {
    const scale = VIEWS[viewKey][2] / 360
    const pins = [...clusters.values()]
      .map((c) => ({ ...c, shown: c.elements.filter(visible) }))
      .filter((c) => c.shown.length)
      .sort((a, b) => b.shown.length - a.shown.length)
      .map((c) => {
        const r = (1.6 + Math.sqrt(c.shown.length) * 1.5) * Math.max(0.16, scale) ** 0.9
        const last = c.shown[c.shown.length - 1]
        const color = lens.classes[last.discoveryMethod]?.color ?? "#888"
        const ancient = c.shown.every((el) => el.ancient)
        const x = c.lon + 180
        const y = 90 - c.lat
        return `<g class="pb-pin${selectedKey === c.key ? " is-selected" : ""}${ancient ? " is-ancient" : ""}" data-key="${c.key}" tabindex="0" role="button" aria-label="${esc(placeName(c))}: ${c.shown.map((e) => e.name).join(", ")}">
          <circle cx="${x}" cy="${y}" r="${r}" style="--pin:${color}"/>
          ${c.shown.length > 1 ? `<text x="${x}" y="${y + r * 0.36}" style="font-size:${r * 1.05}px">${c.shown.length}</text>` : ""}
        </g>`
      })
      .join("")
    $('[data-out="pins"]').innerHTML = pins
    $('[data-out="year"]').textContent = `${yearLabel(year)} · ${ctx.elements.filter(visible).length} known`
  }

  const drawSide = () => {
    const side = $('[data-out="side"]')
    const cluster = selectedKey ? clusters.get(selectedKey) : null
    if (cluster) {
      const shown = cluster.elements.filter(visible)
      side.innerHTML = `
        <h3 class="pb-title">${esc(placeName(cluster))}</h3>
        <p class="pb-note">${shown.length} element${shown.length === 1 ? "" : "s"}${shown.length ? ` · ${yearLabel(yearOf(shown[0]))}–${yearLabel(yearOf(shown[shown.length - 1]))}` : ""}</p>
        <ul class="pb-map-list">${shown.map((el) => `<li><button type="button" class="pb-map-el" data-open="${el.number}" data-category="${el.category}"><b>${el.symbol}</b><span>${esc(el.name)}<small>${yearLabel(yearOf(el))} · ${esc(el.discoveredBy || "")}</small></span></button></li>`).join("")}</ul>
        <div class="pb-actions"><button type="button" class="pb-btn pb-btn--ghost" data-act="tray">Put in tray</button><button type="button" class="pb-btn pb-btn--ghost" data-act="back">All places</button></div>`
      return
    }
    const byPlace = [...clusters.values()].map((c) => [placeName(c), c.elements.filter(visible).length, c.key]).filter(([, n]) => n).sort((a, b) => b[1] - a[1]).slice(0, 10)
    const byCountry = new Map()
    ctx.elements.filter(visible).forEach((el) => { const k = country(el.discoveryPlace); byCountry.set(k, (byCountry.get(k) || 0) + 1) })
    const topCountries = [...byCountry.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8)
    const max = byPlace[0]?.[1] || 1
    side.innerHTML = `
      <h3 class="pb-title">Most productive places</h3>
      <ol class="pb-rank-bars">${byPlace.map(([name, n, key]) => `<li><button type="button" class="pb-link" data-key="${key}">${esc(name)}</button><span class="pb-bar"><span style="width:${(n / max) * 100}%"></span></span><b>${n}</b></li>`).join("")}</ol>
      <h3 class="pb-title">By country / region</h3>
      <p class="pb-note">${topCountries.map(([k, n]) => `${esc(k)} ${n}`).join(" · ")}</p>
      <p class="pb-note">Discovery followed instruments and institutions: Stockholm/Uppsala mineral chemists (rare earths), Davy's voltaic pile in London, Bunsen's spectroscope in Heidelberg, the Curies in Paris, and later the accelerators of Berkeley, Dubna, Darmstadt and Wako.</p>`
  }

  const render = () => { drawPins(); drawSide() }

  const setView = (key) => {
    viewKey = key
    svg.setAttribute("viewBox", VIEWS[key].join(" "))
    panel.querySelectorAll("[data-view]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === key)))
    drawPins()
  }

  const select = (key) => {
    selectedKey = key
    const c = key ? clusters.get(key) : null
    if (c) ctx.highlight(c.elements.filter(visible).map((el) => el.number), `Discovered or first used in ${placeName(c)}`)
    else ctx.highlight(null)
    render()
  }

  const stop = () => {
    clearInterval(timer)
    timer = null
    const b = panel.querySelector('[data-act="play"]')
    if (b) b.textContent = "▶"
  }

  const handlers = {
    click: (e) => {
      const pin = e.target.closest(".pb-pin")
      if (pin) { select(pin.dataset.key === selectedKey ? null : pin.dataset.key); return }
      const keyBtn = e.target.closest("[data-key]")
      if (keyBtn) { select(keyBtn.dataset.key); return }
      const open = e.target.closest("[data-open]")
      if (open) { ctx.openElement(Number(open.dataset.open)); return }
      const view = e.target.closest("[data-view]")
      if (view) { setView(view.dataset.view); return }
      const act = e.target.closest("[data-act]")?.dataset.act
      if (act === "back") select(null)
      if (act === "tray" && selectedKey) ctx.setTray(clusters.get(selectedKey).elements.filter(visible).map((el) => el.symbol))
      if (act === "play") {
        if (timer) { stop(); return }
        if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) { year = 2010; $('[data-in="year"]').value = year; render(); return }
        if (year >= 2010) year = -9000
        e.target.textContent = "❚❚"
        timer = setInterval(() => {
          year = Math.min(2010, year + (year < 0 ? 150 : year < 1600 ? 40 : year < 1950 ? 3 : 2))
          $('[data-in="year"]').value = year
          drawPins()
          if (year >= 2010) stop()
        }, 60)
      }
    },
    input: (e) => {
      if (e.target.dataset.in !== "year") return
      year = Number(e.target.value)
      render()
    },
    keydown: (e) => {
      const pin = e.target.closest(".pb-pin")
      if (pin && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); select(pin.dataset.key) }
    },
    mouseover: (e) => {
      const pin = e.target.closest(".pb-pin")
      const tip = $('[data-out="tip"]')
      if (!pin) { tip.hidden = true; return }
      const c = clusters.get(pin.dataset.key)
      const shown = c.elements.filter(visible)
      tip.hidden = false
      tip.innerHTML = `<b>${esc(placeName(c))}</b><br>${shown.map((el) => `${el.symbol} ${yearLabel(yearOf(el))}`).join(" · ")}`
      const fig = panel.querySelector(".pb-map-figure").getBoundingClientRect()
      const r = pin.getBoundingClientRect()
      tip.style.left = `${Math.min(fig.width - 200, r.right - fig.left + 6)}px`
      tip.style.top = `${r.top - fig.top - 6}px`
    }
  }
  for (const [type, fn] of Object.entries(handlers)) panel.addEventListener(type, fn)

  import("lib/periodic_table/world").then(({ LAND_PATH }) => $('[data-out="land"]').setAttribute("d", LAND_PATH))
  render()

  return {
    update(next) { ctx = next },
    focus(opts = {}) {
      if (!opts.z) return
      const el = ctx.elements[opts.z - 1]
      const c = [...clusters.values()].find((cl) => cl.elements.includes(el))
      if (!c) return
      if (yearOf(el) > year) { year = 2010; $('[data-in="year"]').value = year }
      setView(c.lon > -30 && c.lon < 45 && c.lat > 34 ? "europe" : c.lon < -30 ? "americas" : c.lon > 60 ? "asia" : "world")
      select(c.key)
    },
    highlightCleared() { if (selectedKey) { selectedKey = null; render() } },
    destroy() {
      stop()
      for (const [type, fn] of Object.entries(handlers)) panel.removeEventListener(type, fn)
    }
  }
}
