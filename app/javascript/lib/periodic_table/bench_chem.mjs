// Chemistry bench instruments: Combine, Formula, Equation, Alloy.
// Each mount*(panel, ctx) renders into `panel` and returns { update, focus, destroy }.
// ctx = { elements, bySymbol, chem, trends, compounds, tray, openElement, highlight, setTray, openTab }

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
const signed = (n) => (n > 0 ? `+${n}` : `${n}`)

function on(panel, type, selector, fn) {
  const handler = (e) => {
    const target = e.target.closest(selector)
    if (target && panel.contains(target)) fn(e, target)
  }
  panel.addEventListener(type, handler)
  return () => panel.removeEventListener(type, handler)
}

function compositionBar(rows, key = "massPct") {
  return `<div class="pb-compbar" role="img" aria-label="Composition by ${key === "massPct" ? "mass" : "atoms"}">${rows
    .map((r, i) => `<span style="width:${r[key].toFixed(3)}%;--k:${i}" title="${esc(r.symbol)} ${r[key].toFixed(2)}%"><b>${r[key] > 7 ? esc(r.symbol) : ""}</b></span>`)
    .join("")}</div>`
}

// Compounds from the curated library containing every symbol in `symbols`.
function libraryMatches(ctx, symbols, { exact = false } = {}) {
  const { chem, compounds, bySymbol } = ctx
  const out = []
  for (const [formula, name, cls, note] of compounds.COMPOUNDS) {
    const parseable = compounds.FORMULA_ALIASES[formula] ?? formula
    let counts
    try {
      counts = chem.parseFormula(parseable, bySymbol).counts
    } catch {
      continue
    }
    const keys = [...counts.keys()].map((k) => (k === "D" || k === "T" ? "H" : k))
    if (!symbols.every((s) => keys.includes(s))) continue
    if (exact && keys.some((k) => !symbols.includes(k))) continue
    out.push({ formula, parseable, name, cls, note, mass: chem.molarMass(counts, bySymbol).mass })
  }
  return out
}

// Hill formulas of every library compound, computed once per dataset.
let hillIndex = null
function libraryHillSet(ctx) {
  if (hillIndex) return hillIndex
  hillIndex = new Set()
  for (const [formula] of ctx.compounds.COMPOUNDS) {
    try {
      hillIndex.add(ctx.chem.hillFormula(ctx.chem.parseFormula(ctx.compounds.FORMULA_ALIASES[formula] ?? formula, ctx.bySymbol).counts))
    } catch {
      // validated in tests
    }
  }
  return hillIndex
}

const EXAMPLE_SETS = [["Na", "Cl"], ["Fe", "O"], ["Al", "O"], ["Ga", "As"], ["Si", "C"], ["Li", "Co", "O"], ["Nd", "Fe", "B"], ["Y", "Ba", "Cu", "O"], ["Ti", "N"], ["Cu", "Zn"]]

// ── Combine ───────────────────────────────────────────────────────────
export function mountCombine(panel, initialCtx) {
  let ctx = initialCtx
  let counts = {}
  let states = {}
  let exactOnly = false

  const els = () => ctx.tray.map((s) => ctx.bySymbol.get(s)).filter(Boolean)

  const defaultState = (el, list) => {
    const main = (el.oxidationMain?.length ? el.oxidationMain : el.oxidationStates) || []
    const enMax = Math.max(...list.map((e) => e.electronegativity ?? 0))
    const negative = main.filter((s) => s < 0)
    if ((el.electronegativity ?? 0) === enMax && list.length > 1 && negative.length) return negative[0]
    const pos = main.filter((s) => s > 0)
    return pos.length ? pos[0] : main[0] ?? 0
  }

  const syncState = () => {
    const list = els()
    const next = {}
    const nextStates = {}
    for (const el of list) {
      next[el.symbol] = counts[el.symbol] ?? 1
      nextStates[el.symbol] = states[el.symbol] ?? defaultState(el, list)
    }
    counts = next
    states = nextStates
  }

  // Smallest positive counts (≤ 12 each) giving zero net charge.
  const autoBalance = () => {
    const list = els()
    const ox = list.map((el) => states[el.symbol])
    if (!ox.some((s) => s > 0) || !ox.some((s) => s < 0)) return false
    let best = null
    const search = (i, acc) => {
      if (best && acc.reduce((a, b) => a + b, 0) >= best.reduce((a, b) => a + b, 0)) return
      if (i === list.length) {
        if (acc.reduce((sum, n, k) => sum + n * ox[k], 0) === 0) best = [...acc]
        return
      }
      for (let n = 1; n <= 12; n++) search(i + 1, [...acc, n])
    }
    search(0, [])
    if (!best) return false
    list.forEach((el, i) => { counts[el.symbol] = best[i] })
    return true
  }

  const builtFormula = () => {
    const list = els().slice().sort((a, b) => (states[a.symbol] - states[b.symbol]) * -1 || (a.electronegativity ?? 0) - (b.electronegativity ?? 0))
    return list.map((el) => `${el.symbol}${counts[el.symbol] === 1 ? "" : counts[el.symbol]}`).join("")
  }

  const render = () => {
    syncState()
    const list = els()
    const { chem, bySymbol } = ctx
    if (list.length < 1) {
      panel.innerHTML = `
        <div class="pb-empty">
          <h3 class="pb-title">Combine elements into compounds</h3>
          <p>Collect two or more elements in the tray — shift-click tiles, press <kbd>+</kbd> on a focused tile, or start from a classic pair:</p>
          <div class="pb-examples">${EXAMPLE_SETS.map((set) => `<button type="button" class="pb-example" data-set="${set.join(" ")}">${set.join(" + ")}</button>`).join("")}</div>
          <p class="pb-note">The bench balances oxidation states into neutral formulas, names them (IUPAC), estimates bond character from electronegativity, and finds matching compounds, minerals and alloys in the reference library.</p>
        </div>`
      return
    }

    const formula = builtFormula()
    const parsed = chem.parseFormula(formula, bySymbol)
    const mm = chem.molarMass(parsed.counts, bySymbol)
    const comp = chem.composition(parsed.counts, bySymbol)
    const charge = list.reduce((sum, el) => sum + counts[el.symbol] * states[el.symbol], 0)
    const allMetal = list.every((el) => chem.isMetal(el))

    const builder = list.map((el) => {
      const pool = [...new Set([...(el.oxidationMain || []), ...(el.oxidationStates || [])])].sort((a, b) => b - a)
      const opts = pool.map((s) => `<option value="${s}" ${s === states[el.symbol] ? "selected" : ""}>${signed(s)}${(el.oxidationMain || []).includes(s) ? " ●" : ""}</option>`).join("")
      return `
        <div class="pb-atom" data-category="${el.category}">
          <button type="button" class="pb-atom-sym" data-open="${el.number}" title="Open ${esc(el.name)}">${el.symbol}</button>
          <div class="pb-stepper" role="group" aria-label="${esc(el.name)} count">
            <button type="button" data-step="-1" data-sym="${el.symbol}" aria-label="Fewer ${esc(el.name)}">−</button>
            <output>${counts[el.symbol]}</output>
            <button type="button" data-step="1" data-sym="${el.symbol}" aria-label="More ${esc(el.name)}">+</button>
          </div>
          <label class="pb-ox">ox. <select data-ox="${el.symbol}" aria-label="${esc(el.name)} oxidation state">${opts}</select></label>
        </div>`
    }).join("")

    const balanceBadge = allMetal
      ? `<span class="pb-badge pb-badge--info">metallic — no ionic charge balance</span>`
      : charge === 0
        ? `<span class="pb-badge pb-badge--ok">charge balanced ✓</span>`
        : `<span class="pb-badge pb-badge--warn">net charge ${signed(charge)}</span>`

    const pairs = []
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) pairs.push([list[i], list[j]])
    const bondRows = pairs.map(([a, b]) => {
      const bc = chem.bondCharacter(a, b)
      const pct = bc.ionicPct ?? 0
      return `<div class="pb-bond"><span>${a.symbol}–${b.symbol}</span><span class="pb-bond-track" title="${bc.ionicPct != null ? `${Math.round(pct)}% ionic character` : ""}"><span style="width:${pct}%"></span></span><b>${esc(bc.kind)}</b><small>${bc.delta != null ? `Δχ ${bc.delta.toFixed(2)}` : ""}</small></div>`
    }).join("")

    const predictions = pairs.flatMap(([a, b]) => chem.predictBinaries(a, b).map((c) => ({ ...c, a, b })))
    const library = libraryMatches(ctx, list.map((e) => e.symbol), { exact: exactOnly })
    const libraryHill = libraryHillSet(ctx)
    const predictionRows = predictions.map((c) => {
      const cc = chem.parseFormula(c.formula, bySymbol).counts
      const known = libraryHill.has(chem.hillFormula(cc))
      const bc = chem.bondCharacter(c.a, c.b)
      return `<tr><td><button type="button" class="pb-formula-btn" data-load="${c.formula}" data-states="${c.cation}:${c.cationState},${c.anion}:${c.anionState}">${chem.formulaHTML(c.formula)}</button></td><td>${esc(c.name)}</td><td>${signed(c.cationState)} / ${signed(c.anionState)}</td><td>${chem.sig(chem.molarMass(cc, bySymbol).mass, 5)}</td><td>${esc(bc.kind)}</td><td>${known ? '<span class="pb-tag">catalogued</span>' : '<span class="pb-tag pb-tag--muted">predicted</span>'}</td></tr>`
    }).join("")

    const alloys = ctx.compounds.ALLOYS.filter(([, comp]) => list.every((el) => comp[el.symbol] != null))

    panel.innerHTML = `
      <div class="pb-grid pb-grid--combine">
        <section class="pb-card pb-card--hero">
          <header class="pb-card-head"><h3 class="pb-title">Build</h3>${balanceBadge}</header>
          <div class="pb-atoms">${builder}</div>
          <div class="pb-result">
            <div class="pb-result-formula">${chem.formulaHTML(formula)}</div>
            <dl class="pb-kv">
              <div><dt>Molar mass</dt><dd>${chem.sig(mm.mass, 6)} g/mol${mm.uncertainty ? ` <small>± ${chem.sig(mm.uncertainty, 2)}</small>` : ""}</dd></div>
              <div><dt>Hill formula</dt><dd>${esc(chem.hillFormula(parsed.counts))}</dd></div>
              <div><dt>Atoms per formula unit</dt><dd>${[...parsed.counts.values()].reduce((a, b) => a + b, 0)}</dd></div>
            </dl>
            ${compositionBar(comp)}
            <div class="pb-actions">
              <button type="button" class="pb-btn" data-act="balance" ${allMetal ? "disabled" : ""}>Balance charges</button>
              <button type="button" class="pb-btn pb-btn--ghost" data-act="to-formula">Analyse in Formula →</button>
              ${allMetal ? `<button type="button" class="pb-btn pb-btn--ghost" data-act="to-alloy">Design as an alloy →</button>` : ""}
            </div>
          </div>
          <p class="pb-note">● marks common oxidation states. Neutral ionic formulas satisfy Σ(count × oxidation state) = 0. Cations are written first, in order of increasing electronegativity.</p>
        </section>

        <section class="pb-card">
          <h3 class="pb-title">Bond character</h3>
          <div class="pb-bonds">${bondRows || `<p class="pb-note">Add a second element to compare bonding.</p>`}</div>
          <p class="pb-note">Pauling's estimate of ionic character, 1 − e^(−Δχ²/4). Δχ < 0.4 nonpolar covalent · 0.4–1.7 polar covalent · > 1.7 ionic. Two metals bond metallically.</p>
        </section>

        <section class="pb-card pb-card--wide">
          <h3 class="pb-title">Charge-balanced binaries</h3>
          ${predictionRows
            ? `<div class="pb-table-wrap"><table class="pb-table"><thead><tr><th>Formula</th><th>Name</th><th>Ox. states</th><th>M / g·mol⁻¹</th><th>Bond</th><th></th></tr></thead><tbody>${predictionRows}</tbody></table></div>`
            : `<p class="pb-note">${allMetal ? "Metals don't charge-balance against each other — they form alloys and intermetallic compounds (see below and the Alloy tab)." : "No oppositely charged common oxidation states among these elements."}</p>`}
        </section>

        <section class="pb-card pb-card--wide">
          <header class="pb-card-head">
            <h3 class="pb-title">In the reference library <small>${library.length}</small></h3>
            <label class="pb-check"><input type="checkbox" data-act="exact" ${exactOnly ? "checked" : ""}> only these elements</label>
          </header>
          ${library.length
            ? `<ul class="pb-library">${library.map((c) => `<li><button type="button" class="pb-formula-btn" data-formula="${esc(c.parseable)}">${ctx.chem.formulaHTML(c.formula)}</button><div><b>${esc(c.name)}</b><small>${esc(ctx.compounds.COMPOUND_CLASSES[c.cls] || c.cls)} · ${ctx.chem.sig(c.mass, 5)} g/mol</small><p>${esc(c.note)}</p></div></li>`).join("")}</ul>`
            : `<p class="pb-note">No catalogued compound contains ${list.map((e) => e.symbol).join(" + ")}${exactOnly ? " alone" : ""}. That can mean an unexplored combination — or one that is thermodynamically unfavourable.</p>`}
          ${alloys.length ? `<h4 class="pb-subtitle">Alloys</h4><ul class="pb-alloy-list">${alloys.map(([name, comp]) => `<li><button type="button" class="pb-link" data-alloy="${esc(name)}">${esc(name)}</button> <small>${list.map((el) => `${el.symbol} ${comp[el.symbol]}%`).join(" · ")}</small></li>`).join("")}</ul>` : ""}
        </section>
      </div>`
  }

  const offs = [
    on(panel, "click", "[data-set]", (_e, b) => ctx.setTray(b.dataset.set.split(" "))),
    on(panel, "click", "[data-open]", (_e, b) => ctx.openElement(Number(b.dataset.open))),
    on(panel, "click", "[data-step]", (_e, b) => {
      const s = b.dataset.sym
      counts[s] = Math.max(1, Math.min(99, (counts[s] || 1) + Number(b.dataset.step)))
      render()
    }),
    on(panel, "change", "[data-ox]", (_e, sel) => {
      states[sel.dataset.ox] = Number(sel.value)
      render()
    }),
    on(panel, "click", "[data-act]", (e, b) => {
      const act = b.dataset.act
      if (act === "balance") { autoBalance(); render() }
      if (act === "to-formula") ctx.openTab("formula", { formula: builtFormula() })
      if (act === "to-alloy") ctx.openTab("alloy", { fromTray: true })
      if (act === "exact") { exactOnly = e.target.checked; render() }
    }),
    on(panel, "click", "[data-load]", (_e, b) => {
      const parsed = ctx.chem.parseFormula(b.dataset.load, ctx.bySymbol)
      for (const pair of b.dataset.states.split(",")) {
        const [sym, st] = pair.split(":")
        states[sym] = Number(st)
      }
      for (const [sym, n] of parsed.counts) counts[sym] = n
      for (const s of ctx.tray) if (!parsed.counts.has(s)) counts[s] = counts[s] ?? 1
      render()
      panel.querySelector(".pb-card--hero")?.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }),
    on(panel, "click", "[data-formula]", (_e, b) => ctx.openTab("formula", { formula: b.dataset.formula })),
    on(panel, "click", "[data-alloy]", (_e, b) => ctx.openTab("alloy", { preset: b.dataset.alloy }))
  ]

  // A new tray starts from the smallest charge-neutral formula.
  const freshStart = () => {
    syncState()
    if (els().length > 1) autoBalance()
    render()
  }

  freshStart()
  return {
    update(next) {
      const changed = next.tray.join() !== ctx.tray.join()
      ctx = next
      if (changed) { counts = {}; states = {}; freshStart() } else render()
    },
    destroy() { offs.forEach((off) => off()) }
  }
}

// ── Formula ───────────────────────────────────────────────────────────
const FORMULA_EXAMPLES = ["H2O", "C6H12O6", "CuSO4·5H2O", "Ca10(PO4)6(OH)2", "K4[Fe(CN)6]", "YBa2Cu3O7", "LiFePO4", "C8H10N4O2"]

export function mountFormula(panel, initialCtx) {
  let ctx = initialCtx
  let formula = "C6H12O6"
  let grams = 10
  let molarity = 0.1
  let volumeMl = 250
  let purity = 100
  let percentText = "C 40.0\nH 6.71\nO 53.29"
  let knownMolarMass = ""
  let formulaMass = null

  panel.innerHTML = `
    <div class="pb-grid pb-grid--formula">
      <section class="pb-card pb-card--hero">
        <label class="pb-field pb-field--big">
          <span>Formula</span>
          <input type="text" data-in="formula" spellcheck="false" autocomplete="off" aria-describedby="pb-formula-help">
        </label>
        <p class="pb-help" id="pb-formula-help">Parentheses and brackets nest; hydrates with · or * (CuSO4·5H2O); decimals for non-stoichiometry (Fe0.95O); charges with ^ (SO4^2-); D and T for heavy hydrogen.</p>
        <div class="pb-examples">${FORMULA_EXAMPLES.map((f) => `<button type="button" class="pb-example" data-example="${esc(f)}">${esc(f)}</button>`).join("")}</div>
        <div data-out="analysis"></div>
      </section>
      <section class="pb-card">
        <h3 class="pb-title">Amount</h3>
        <div class="pb-fields">
          <label class="pb-field"><span>Mass (g)</span><input type="number" step="any" min="0" data-in="grams"></label>
        </div>
        <div data-out="amount"></div>
        <h3 class="pb-title">Make a solution</h3>
        <div class="pb-fields">
          <label class="pb-field"><span>Concentration (mol/L)</span><input type="number" step="any" min="0" data-in="molarity"></label>
          <label class="pb-field"><span>Volume (mL)</span><input type="number" step="any" min="0" data-in="volume"></label>
          <label class="pb-field"><span>Reagent purity (%)</span><input type="number" step="any" min="1" max="100" data-in="purity"></label>
        </div>
        <div data-out="solution"></div>
      </section>
      <section class="pb-card">
        <h3 class="pb-title">Empirical formula from analysis</h3>
        <p class="pb-help">One element and its mass % per line (combustion or ICP results).</p>
        <textarea class="pb-textarea" rows="4" data-in="percent" spellcheck="false" aria-label="Mass percentages"></textarea>
        <label class="pb-field"><span>Measured molar mass (optional, g/mol)</span><input type="number" step="any" min="0" data-in="known"></label>
        <div data-out="empirical"></div>
      </section>
    </div>`

  const $ = (sel) => panel.querySelector(sel)
  $('[data-in="formula"]').value = formula
  $('[data-in="grams"]').value = grams
  $('[data-in="molarity"]').value = molarity
  $('[data-in="volume"]').value = volumeMl
  $('[data-in="purity"]').value = purity
  $('[data-in="percent"]').value = percentText

  const analyse = () => {
    const { chem, bySymbol } = ctx
    const out = $('[data-out="analysis"]')
    try {
      const parsed = chem.parseFormula(formula, bySymbol)
      const mm = chem.molarMass(parsed.counts, bySymbol)
      const comp = chem.composition(parsed.counts, bySymbol)
      const atoms = [...parsed.counts.values()].reduce((a, b) => a + b, 0)
      out.innerHTML = `
        <div class="pb-result">
          <div class="pb-result-formula">${chem.formulaHTML(formula.replace(/\s+/g, ""))}</div>
          <dl class="pb-kv">
            <div><dt>Molar mass</dt><dd><b>${chem.sig(mm.mass, 7)}</b> g/mol${mm.uncertainty ? ` <small>± ${chem.sig(mm.uncertainty, 2)}</small>` : ""}${mm.approximate ? ` <small>(contains elements without a standard atomic weight)</small>` : ""}</dd></div>
            <div><dt>Hill formula</dt><dd>${esc(chem.hillFormula(parsed.counts))}</dd></div>
            <div><dt>Atoms / formula unit</dt><dd>${chem.fmtCount(atoms)}</dd></div>
            ${parsed.charge ? `<div><dt>Charge</dt><dd>${signed(parsed.charge)}</dd></div>` : ""}
          </dl>
          ${compositionBar(comp)}
          <div class="pb-table-wrap"><table class="pb-table">
            <thead><tr><th>Element</th><th>Count</th><th>Atomic wt.</th><th>Mass / g·mol⁻¹</th><th>Mass %</th><th>Atom %</th></tr></thead>
            <tbody>${comp.map((c) => {
              const el = bySymbol.get(c.symbol)
              return `<tr><td><button type="button" class="pb-link" data-open="${el.number}">${esc(c.symbol)}</button> <small>${esc(el.name)}</small></td><td>${chem.fmtCount(c.count)}</td><td>${chem.sig(el.atomicWeight ?? el.mass, 7)}</td><td>${chem.sig(c.mass, 6)}</td><td>${c.massPct.toFixed(3)}</td><td>${c.molePct.toFixed(2)}</td></tr>`
            }).join("")}</tbody>
          </table></div>
          <div class="pb-actions"><button type="button" class="pb-btn pb-btn--ghost" data-act="highlight">Highlight these elements on the table</button>
          <button type="button" class="pb-btn pb-btn--ghost" data-act="tray">Put them in the tray</button></div>
        </div>`
      formulaMass = mm.mass
    } catch (e) {
      formulaMass = null
      out.innerHTML = `<p class="pb-error" role="alert">${esc(e.message)}</p>`
    }
    amounts()
  }

  const amounts = () => {
    const { chem } = ctx
    const a = $('[data-out="amount"]')
    const s = $('[data-out="solution"]')
    if (!formulaMass) { a.innerHTML = ""; s.innerHTML = ""; return }
    const mol = grams / formulaMass
    a.innerHTML = `<dl class="pb-kv">
      <div><dt>Moles</dt><dd>${chem.sig(mol, 5)} mol</dd></div>
      <div><dt>Formula units</dt><dd>${chem.sig(mol * chem.AVOGADRO, 4)}</dd></div>
      <div><dt>Gas volume (0 °C, 1 atm)</dt><dd>${chem.sig(mol * 22.414, 4)} L</dd></div>
      <div><dt>Gas volume (25 °C, 1 bar)</dt><dd>${chem.sig(mol * 24.789, 4)} L</dd></div>
    </dl>`
    const need = (molarity * volumeMl) / 1000 * formulaMass / (purity / 100)
    s.innerHTML = `<p class="pb-answer">Weigh <b>${chem.sig(need, 4)} g</b> and make up to ${chem.sig(volumeMl, 4)} mL.</p><p class="pb-note">${chem.sig((molarity * volumeMl) / 1000, 4)} mol × ${chem.sig(formulaMass, 6)} g/mol${purity < 100 ? ` ÷ ${purity}% purity` : ""}. For a dilution use C₁V₁ = C₂V₂.</p>`
  }

  const empirical = () => {
    const { chem, bySymbol } = ctx
    const out = $('[data-out="empirical"]')
    const pct = {}
    for (const line of percentText.split(/[\n,;]+/)) {
      const m = line.trim().match(/^([A-Z][a-z]?)\s*[:=]?\s*([\d.]+)\s*%?$/)
      if (m) pct[m[1]] = (pct[m[1]] || 0) + Number(m[2])
    }
    try {
      const total = Object.values(pct).reduce((a, b) => a + b, 0)
      const res = chem.empiricalFromPercent(pct, bySymbol)
      const emp = [...res.counts].map(([s, n]) => `${s}${n === 1 ? "" : n}`).join("")
      const empMass = chem.molarMass(res.counts, bySymbol).mass
      let molecular = ""
      const known = Number(knownMolarMass)
      if (known > 0) {
        const k = Math.max(1, Math.round(known / empMass))
        const mol = [...res.counts].map(([s, n]) => `${s}${n * k === 1 ? "" : n * k}`).join("")
        molecular = `<div><dt>Molecular formula</dt><dd><button type="button" class="pb-formula-btn" data-example="${mol}">${chem.formulaHTML(mol)}</button> <small>(× ${k})</small></dd></div>`
      }
      out.innerHTML = `<dl class="pb-kv">
        <div><dt>Empirical formula</dt><dd><button type="button" class="pb-formula-btn" data-example="${emp}">${chem.formulaHTML(emp)}</button>${res.approximate ? ` <small>(approximate fit)</small>` : ""}</dd></div>
        <div><dt>Empirical mass</dt><dd>${chem.sig(empMass, 6)} g/mol</dd></div>
        ${molecular}
        <div><dt>Mole ratios</dt><dd>${Object.entries(res.ratios).map(([s, r]) => `${s} ${r.toFixed(3)}`).join(" : ")}</dd></div>
      </dl>${Math.abs(total - 100) > 1.5 ? `<p class="pb-note">Percentages sum to ${total.toFixed(2)}% — oxygen is often reported by difference.</p>` : ""}`
    } catch (e) {
      out.innerHTML = `<p class="pb-error" role="alert">${esc(e.message)}</p>`
    }
  }

  const offs = [
    on(panel, "input", "[data-in]", (_e, input) => {
      const k = input.dataset.in
      if (k === "formula") { formula = input.value; analyse() }
      if (k === "grams") { grams = Number(input.value) || 0; amounts() }
      if (k === "molarity") { molarity = Number(input.value) || 0; amounts() }
      if (k === "volume") { volumeMl = Number(input.value) || 0; amounts() }
      if (k === "purity") { purity = Math.min(100, Math.max(1, Number(input.value) || 100)); amounts() }
      if (k === "percent") { percentText = input.value; empirical() }
      if (k === "known") { knownMolarMass = input.value; empirical() }
    }),
    on(panel, "click", "[data-example]", (_e, b) => {
      formula = b.dataset.example
      $('[data-in="formula"]').value = formula
      analyse()
      $('[data-in="formula"]').focus()
    }),
    on(panel, "click", "[data-open]", (_e, b) => ctx.openElement(Number(b.dataset.open))),
    on(panel, "click", "[data-act]", (_e, b) => {
      try {
        const parsed = ctx.chem.parseFormula(formula, ctx.bySymbol)
        const syms = [...parsed.counts.keys()].map((s) => (s === "D" || s === "T" ? "H" : s))
        if (b.dataset.act === "highlight") ctx.highlight(syms.map((s) => ctx.bySymbol.get(s).number), `Elements in ${formula}`)
        if (b.dataset.act === "tray") ctx.setTray(syms)
      } catch {
        // invalid formula: buttons do nothing (error already shown)
      }
    })
  ]

  analyse()
  empirical()
  return {
    update(next) { ctx = next },
    focus(opts = {}) {
      if (opts.formula) {
        formula = opts.formula
        $('[data-in="formula"]').value = formula
        analyse()
      }
    },
    destroy() { offs.forEach((off) => off()) }
  }
}

// ── Equation ──────────────────────────────────────────────────────────
const EQUATION_EXAMPLES = [
  "Fe2O3 + CO -> Fe + CO2",
  "C3H8 + O2 -> CO2 + H2O",
  "Al + Fe2O3 -> Al2O3 + Fe",
  "KMnO4 + HCl -> KCl + MnCl2 + H2O + Cl2",
  "Cu + HNO3 -> Cu(NO3)2 + NO + H2O",
  "MnO4^- + Fe^2+ + H^+ -> Mn^2+ + Fe^3+ + H2O",
  "Ca10(PO4)6(OH)2 + H2SO4 -> CaSO4 + H3PO4 + H2O",
  "TiCl4 + Mg -> Ti + MgCl2"
]

export function mountEquation(panel, initialCtx) {
  let ctx = initialCtx
  let equation = EQUATION_EXAMPLES[0]
  let balanced = null
  const given = {}

  panel.innerHTML = `
    <div class="pb-grid pb-grid--equation">
      <section class="pb-card pb-card--hero">
        <label class="pb-field pb-field--big">
          <span>Reaction</span>
          <input type="text" data-in="equation" spellcheck="false" autocomplete="off" aria-describedby="pb-eq-help">
        </label>
        <p class="pb-help" id="pb-eq-help">Separate species with “+”, sides with -> or =. Ions with ^ (Fe^3+), electrons as e. Existing coefficients are ignored.</p>
        <div class="pb-examples">${EQUATION_EXAMPLES.map((f) => `<button type="button" class="pb-example" data-example="${esc(f)}">${esc(f.replace("->", "→"))}</button>`).join("")}</div>
        <div data-out="balanced" aria-live="polite"></div>
      </section>
      <section class="pb-card pb-card--wide" data-out="stoich"></section>
    </div>`

  const $ = (sel) => panel.querySelector(sel)
  $('[data-in="equation"]').value = equation

  const pretty = (species, chem) => {
    const side = (s) => species.filter((x) => x.side === s).map((x) => `<span class="pb-species">${x.coefficient === 1 ? "" : `<b class="pb-coeff">${x.coefficient}</b>`}${chem.formulaHTML(x.formula)}</span>`).join('<span class="pb-plus">+</span>')
    return `${side("reactant")}<span class="pb-arrow">→</span>${side("product")}`
  }

  const atomCheck = (species) => {
    const { chem, bySymbol } = ctx
    const tally = { reactant: new Map(), product: new Map() }
    for (const s of species) {
      if (/^e(\^?-)?$/.test(s.formula)) continue
      for (const [sym, n] of chem.parseFormula(s.formula, bySymbol).counts) tally[s.side].set(sym, (tally[s.side].get(sym) || 0) + n * s.coefficient)
    }
    const charge = (side) => species.filter((s) => s.side === side).reduce((a, s) => a + s.charge * s.coefficient, 0)
    const syms = [...new Set([...tally.reactant.keys(), ...tally.product.keys()])]
    return `<table class="pb-table pb-table--compact"><thead><tr><th>Element</th><th>Left</th><th>Right</th></tr></thead><tbody>${syms.map((s) => `<tr><td>${s}</td><td>${chem.fmtCount(tally.reactant.get(s) || 0)}</td><td>${chem.fmtCount(tally.product.get(s) || 0)}</td></tr>`).join("")}${species.some((s) => s.charge) ? `<tr><td>charge</td><td>${signed(charge("reactant"))}</td><td>${signed(charge("product"))}</td></tr>` : ""}</tbody></table>`
  }

  const solve = () => {
    const { chem, bySymbol } = ctx
    const out = $('[data-out="balanced"]')
    try {
      balanced = chem.balanceEquation(equation, bySymbol)
      for (const k of Object.keys(given)) if (Number(k) >= balanced.species.length) delete given[k]
      out.innerHTML = `<div class="pb-equation">${pretty(balanced.species, chem)}</div>
        <details class="pb-details"><summary>Atom bookkeeping</summary>${atomCheck(balanced.species)}</details>
        <button type="button" class="pb-btn pb-btn--ghost" data-act="copy">Copy balanced equation</button>`
    } catch (e) {
      balanced = null
      out.innerHTML = `<p class="pb-error" role="alert">${esc(e.message)}</p>`
    }
    stoich()
  }

  const stoich = () => {
    const { chem } = ctx
    const out = $('[data-out="stoich"]')
    if (!balanced) { out.innerHTML = ""; return }
    const result = chem.stoichiometry(balanced.species, Object.fromEntries(Object.entries(given).map(([k, v]) => [k, Number(v)])))
    const rows = balanced.species.map((s, i) => {
      const r = result?.rows[i]
      const isElectron = s.molarMass === 0
      return `<tr class="${result?.limiting === i ? "is-limiting" : ""}">
        <td>${s.side === "reactant" ? "in" : "out"}</td>
        <td>${s.coefficient}</td>
        <td class="pb-formula-cell">${chem.formulaHTML(s.formula)}</td>
        <td>${isElectron ? "—" : chem.sig(s.molarMass, 6)}</td>
        <td>${isElectron ? "" : `<input type="number" step="any" min="0" class="pb-mini" data-given="${i}" value="${given[i] ?? ""}" aria-label="Grams of ${esc(s.formula)} available">`}</td>
        <td>${r ? chem.sig(r.moles, 4) : ""}</td>
        <td>${r && !isElectron ? `<b>${chem.sig(r.grams, 4)}</b>` : ""}</td>
        <td>${result && given[i] != null && given[i] !== "" && s.side === "reactant" && !isElectron ? `${chem.sig(Math.abs(Number(given[i]) - r.grams) < 1e-9 * Number(given[i]) ? 0 : Number(given[i]) - r.grams, 4)} g left` : result?.limiting === i ? "limiting" : ""}</td>
      </tr>`
    }).join("")
    out.innerHTML = `
      <h3 class="pb-title">Stoichiometry</h3>
      <p class="pb-help">Enter the grams you have of one or more reactants (or a product you want). The smallest moles ÷ coefficient sets the reaction extent — that species is limiting.</p>
      <div class="pb-table-wrap"><table class="pb-table">
        <thead><tr><th></th><th>ν</th><th>Species</th><th>M / g·mol⁻¹</th><th>Have (g)</th><th>Reacts / forms (mol)</th><th>Mass (g)</th><th></th></tr></thead>
        <tbody>${rows}</tbody>
      </table></div>
      ${result ? `<p class="pb-answer">Extent ξ = ${chem.sig(result.extent, 4)} mol · limiting: <b>${esc(balanced.species[result.limiting].formula)}</b></p>` : ""}`
  }

  const offs = [
    on(panel, "input", '[data-in="equation"]', (_e, input) => { equation = input.value; solve() }),
    on(panel, "input", "[data-given]", (_e, input) => {
      given[input.dataset.given] = input.value
      const pos = input.dataset.given
      stoich()
      const again = panel.querySelector(`[data-given="${pos}"]`)
      if (again) { again.focus(); const len = again.value.length; try { again.setSelectionRange(len, len) } catch { /* number inputs */ } }
    }),
    on(panel, "click", "[data-example]", (_e, b) => {
      equation = b.dataset.example
      for (const k of Object.keys(given)) delete given[k]
      $('[data-in="equation"]').value = equation
      solve()
    }),
    on(panel, "click", '[data-act="copy"]', (_e, b) => {
      if (!balanced) return
      navigator.clipboard?.writeText(balanced.text).then(() => { b.textContent = "Copied ✓" }, () => {})
    })
  ]

  solve()
  return {
    update(next) { ctx = next },
    focus(opts = {}) {
      if (opts.equation) {
        equation = opts.equation
        $('[data-in="equation"]').value = equation
        solve()
      }
    },
    destroy() { offs.forEach((off) => off()) }
  }
}

// ── Alloy ─────────────────────────────────────────────────────────────
export function mountAlloy(panel, initialCtx) {
  let ctx = initialCtx
  let basis = "wt"
  let rows = [["Fe", 70], ["Cr", 18], ["Ni", 10], ["Mn", 2]]
  let label = "Custom"

  const familyOptions = () => {
    const { ALLOYS, ALLOY_FAMILIES } = ctx.compounds
    return Object.entries(ALLOY_FAMILIES).map(([fam, famLabel]) => {
      const items = ALLOYS.filter(([, , f]) => f === fam).map(([name]) => `<option value="${esc(name)}">${esc(name)}</option>`).join("")
      return items ? `<optgroup label="${esc(famLabel)}">${items}</optgroup>` : ""
    }).join("")
  }

  panel.innerHTML = `
    <div class="pb-grid pb-grid--alloy">
      <section class="pb-card pb-card--hero">
        <header class="pb-card-head">
          <h3 class="pb-title">Composition</h3>
          <div class="pb-seg" role="group" aria-label="Composition basis">
            <button type="button" data-basis="wt" aria-pressed="true">wt %</button>
            <button type="button" data-basis="at" aria-pressed="false">at %</button>
          </div>
        </header>
        <label class="pb-field"><span>Start from a reference alloy</span>
          <select data-in="preset"><option value="">— choose —</option>${familyOptions()}</select></label>
        <div data-out="rows"></div>
        <div class="pb-actions">
          <button type="button" class="pb-btn pb-btn--ghost" data-act="add">+ Element</button>
          <button type="button" class="pb-btn pb-btn--ghost" data-act="tray">Use tray (equiatomic)</button>
          <button type="button" class="pb-btn pb-btn--ghost" data-act="normalise">Normalise to 100</button>
        </div>
        <p class="pb-note" data-out="preset-note"></p>
      </section>
      <section class="pb-card" data-out="metrics"></section>
      <section class="pb-card pb-card--wide" data-out="hume"></section>
    </div>`

  const $ = (sel) => panel.querySelector(sel)

  const renderRows = () => {
    const opts = (cur) => ctx.elements.filter((el) => el.number <= 103).map((el) => `<option value="${el.symbol}" ${el.symbol === cur ? "selected" : ""}>${el.symbol} — ${esc(el.name)}</option>`).join("")
    const total = rows.reduce((a, [, v]) => a + (Number(v) || 0), 0)
    $('[data-out="rows"]').innerHTML = `
      <div class="pb-alloy-rows">${rows.map(([sym, v], i) => `
        <div class="pb-alloy-row">
          <select data-row-sym="${i}" aria-label="Element ${i + 1}">${opts(sym)}</select>
          <input type="number" step="any" min="0" value="${v}" data-row-val="${i}" aria-label="${basis === "wt" ? "Weight" : "Atomic"} percent of ${sym}">
          <button type="button" class="pb-icon-btn" data-row-del="${i}" aria-label="Remove ${sym}">×</button>
        </div>`).join("")}</div>
      <p class="pb-sum ${Math.abs(total - 100) > 0.01 ? "is-off" : ""}">Σ = ${total.toFixed(2)}% ${Math.abs(total - 100) > 0.01 ? "— results are normalised" : ""}</p>`
  }

  const compute = () => {
    const { chem, bySymbol } = ctx
    const input = {}
    for (const [s, v] of rows) if (Number(v) > 0) input[s] = (input[s] || 0) + Number(v)
    const metricsEl = $('[data-out="metrics"]')
    const humeEl = $('[data-out="hume"]')
    if (!Object.keys(input).length) { metricsEl.innerHTML = ""; humeEl.innerHTML = ""; return }
    const wt = basis === "wt" ? chem.normalise(input) : chem.atToWt(input, bySymbol)
    const at = basis === "at" ? chem.normalise(input) : chem.wtToAt(input, bySymbol)
    const m = chem.alloyMetrics(at, bySymbol)
    const syms = Object.keys(at).sort((a, b) => at[b] - at[a])
    const base = bySymbol.get(syms[0])
    const fmtT = (k) => (k == null ? "—" : `${Math.round(k)} K (${Math.round(k - 273.15)} °C)`)

    metricsEl.innerHTML = `
      <h3 class="pb-title">${esc(label)}</h3>
      <div class="pb-table-wrap"><table class="pb-table pb-table--compact">
        <thead><tr><th>Element</th><th>wt %</th><th>at %</th></tr></thead>
        <tbody>${syms.map((s) => `<tr><td>${s}</td><td>${wt[s].toFixed(3)}</td><td>${at[s].toFixed(3)}</td></tr>`).join("")}</tbody>
      </table></div>
      <dl class="pb-kv">
        <div><dt>Mixing entropy ΔS<sub>mix</sub></dt><dd>${chem.sig(m.deltaSmix, 4)} J/(mol·K) = ${m.deltaSmixR.toFixed(2)} R <span class="pb-tag">${m.entropyClass}</span></dd></div>
        <div><dt>Size mismatch δ</dt><dd>${m.delta != null ? `${m.delta.toFixed(2)} %` : "—"}</dd></div>
        <div><dt>Valence electron conc. (VEC)</dt><dd>${m.vec != null ? m.vec.toFixed(2) : "—"}</dd></div>
        <div><dt>Electronegativity spread Δχ</dt><dd>${m.deltaChi != null ? m.deltaChi.toFixed(3) : "—"}</dd></div>
        <div><dt>Density (ideal mixing)</dt><dd>${m.density != null ? `${m.density.toFixed(3)} g/cm³` : "—"}</dd></div>
        <div><dt>Melting point (rule of mixtures)</dt><dd>${fmtT(m.meltRuleOfMixtures)}</dd></div>
        <div><dt>Mean atomic weight</dt><dd>${m.meanAtomicWeight != null ? m.meanAtomicWeight.toFixed(3) : "—"} g/mol</dd></div>
      </dl>
      ${m.components > 1 ? `<ul class="pb-verdicts">${m.phase ? `<li>${esc(m.phase)} (VEC ≥ 8 → FCC; < 6.87 → BCC)</li>` : ""}${m.solidSolution ? `<li>${esc(m.solidSolution)}</li>` : ""}</ul>` : ""}
      <p class="pb-note">Empirical screening rules for multi-component alloys (Guo 2011; Zhang 2008). They ignore enthalpy of mixing and kinetics — use CALPHAD for real phase diagrams. Density assumes ideal (Vegard-like) mixing.</p>`

    const solutes = syms.slice(1)
    humeEl.innerHTML = solutes.length
      ? `<h3 class="pb-title">Hume-Rothery solubility in ${esc(base.name)}</h3>
        <div class="pb-table-wrap"><table class="pb-table">
          <thead><tr><th>Solute</th><th>Size Δ (&lt;15%)</th><th>Structure</th><th>Δχ (&lt;0.4)</th><th>Valence</th><th>Verdict</th></tr></thead>
          <tbody>${solutes.map((s) => {
            const hr = chem.humeRothery(base, bySymbol.get(s))
            const cell = (r) => `<td class="${r.pass === true ? "is-pass" : r.pass === false ? "is-fail" : ""}">${r.pass === true ? "✓" : r.pass === false ? "✗" : "?"} ${esc(r.detail)}</td>`
            return `<tr><td>${s}</td>${hr.rules.map(cell).join("")}<td>${esc(hr.verdict)}</td></tr>`
          }).join("")}</tbody>
        </table></div>
        <p class="pb-note">Rules for extensive substitutional solid solution (Hume-Rothery 1934), with the most abundant element as solvent. Metallic radii for CN 12; valence = lowest common positive oxidation state.</p>`
      : `<p class="pb-note">Add a second element to check solid solubility.</p>`
  }

  const refresh = () => { renderRows(); compute() }

  const loadPreset = (name) => {
    const found = ctx.compounds.ALLOYS.find(([n]) => n === name)
    if (!found) return
    const [n, comp, fam, note] = found
    basis = "wt"
    rows = Object.entries(comp)
    label = n
    $('[data-out="preset-note"]').textContent = `${ctx.compounds.ALLOY_FAMILIES[fam]} · ${note}`
    paintBasis()
    refresh()
  }

  const paintBasis = () => panel.querySelectorAll("[data-basis]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.basis === basis)))

  const offs = [
    on(panel, "change", '[data-in="preset"]', (_e, sel) => { if (sel.value) loadPreset(sel.value) }),
    on(panel, "click", "[data-basis]", (_e, b) => {
      if (b.dataset.basis === basis) return
      // Convert the current numbers so the composition is preserved.
      const input = Object.fromEntries(rows.filter(([, v]) => Number(v) > 0).map(([s, v]) => [s, Number(v)]))
      const conv = b.dataset.basis === "at" ? ctx.chem.wtToAt(input, ctx.bySymbol) : ctx.chem.atToWt(input, ctx.bySymbol)
      rows = Object.entries(conv).map(([s, v]) => [s, Number(v.toFixed(3))])
      basis = b.dataset.basis
      paintBasis()
      refresh()
    }),
    on(panel, "change", "[data-row-sym]", (_e, sel) => { rows[Number(sel.dataset.rowSym)][0] = sel.value; label = "Custom"; refresh() }),
    on(panel, "input", "[data-row-val]", (_e, input) => { rows[Number(input.dataset.rowVal)][1] = input.value; label = "Custom"; compute(); const total = rows.reduce((a, [, v]) => a + (Number(v) || 0), 0); const sum = panel.querySelector(".pb-sum"); if (sum) { sum.textContent = `Σ = ${total.toFixed(2)}%${Math.abs(total - 100) > 0.01 ? " — results are normalised" : ""}`; sum.classList.toggle("is-off", Math.abs(total - 100) > 0.01) } }),
    on(panel, "click", "[data-row-del]", (_e, b) => { rows.splice(Number(b.dataset.rowDel), 1); refresh() }),
    on(panel, "click", "[data-act]", (_e, b) => {
      const act = b.dataset.act
      if (act === "add") {
        const used = new Set(rows.map(([s]) => s))
        const next = ["Al", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Nb", "Mo", "W"].find((s) => !used.has(s)) || "C"
        rows.push([next, 0])
      }
      if (act === "tray") useTray()
      if (act === "normalise") {
        const total = rows.reduce((a, [, v]) => a + (Number(v) || 0), 0)
        if (total > 0) rows = rows.map(([s, v]) => [s, Number(((Number(v) || 0) / total * 100).toFixed(3))])
      }
      refresh()
    })
  ]

  const useTray = () => {
    const metals = ctx.tray.filter((s) => ctx.bySymbol.has(s))
    if (!metals.length) return
    basis = "at"
    rows = metals.map((s) => [s, Number((100 / metals.length).toFixed(3))])
    label = `Equiatomic ${metals.join("")}`
    paintBasis()
  }

  $('[data-in="preset"]').value = ""
  refresh()
  return {
    update(next) { ctx = next },
    focus(opts = {}) {
      if (opts.preset) { $('[data-in="preset"]').value = opts.preset; loadPreset(opts.preset) }
      if (opts.fromTray) { useTray(); refresh() }
    },
    destroy() { offs.forEach((off) => off()) }
  }
}
