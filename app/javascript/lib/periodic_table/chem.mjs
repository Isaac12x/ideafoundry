// Pure chemistry helpers for the periodic table workbench. No imports, so the
// module runs under plain `node --test` and loads bare in the browser as
// "lib/periodic_table/chem". Callers pass element data in (an index built by
// `indexElements(ELEMENTS)`), keeping this file free of the 300 KB dataset.

export class ChemError extends Error {}

export const R_GAS = 8.314462618 // J/(mol·K)
export const AVOGADRO = 6.02214076e23

// D and T are accepted as hydrogen isotopes (heavy water D2O, tritiated T2O).
const HYDROGEN_ISOTOPES = { D: ["Deuterium", 2.01410178], T: ["Tritium", 3.01604928] }

export function indexElements(elements) {
  const bySymbol = new Map()
  for (const el of elements) bySymbol.set(el.symbol, el)
  const h = bySymbol.get("H")
  if (h) {
    for (const [sym, [name, w]] of Object.entries(HYDROGEN_ISOTOPES)) {
      bySymbol.set(sym, { ...h, symbol: sym, name, mass: w, atomicWeight: w, atomicWeightUncertainty: 0, isotopeOf: "H" })
    }
  }
  return bySymbol
}

const weightOf = (el) => el.atomicWeight ?? el.mass

// ── Formula parsing ────────────────────────────────────────────────────
// Grammar (whitespace ignored):
//   formula := part (("·" | "*" | "•" | ".") part)*  charge?
//   part    := number? group+
//   group   := (Element | "(" group+ ")" | "[" group+ "]" | "{" group+ "}") number?
//   charge  := "^" digits? ("+" | "-")  |  "^" ("+" | "-") digits?
// Counts may be decimal (non-stoichiometric phases, e.g. Fe0.95O).
export function parseFormula(input, bySymbol) {
  if (typeof input !== "string" || !input.trim()) throw new ChemError("Enter a formula")
  let src = input.replace(/\s+/g, "")
  let charge = 0
  const chargeMatch = src.match(/\^(\d*)([+-])(\d*)$/)
  if (chargeMatch) {
    const digits = chargeMatch[1] || chargeMatch[3] || "1"
    charge = Number(digits) * (chargeMatch[2] === "-" ? -1 : 1)
    src = src.slice(0, chargeMatch.index)
  }

  const counts = new Map()
  for (const part of splitHydrate(src)) {
    if (!part) throw new ChemError("Empty part around a hydrate dot")
    let pos = 0
    const lead = part.match(/^\d+(\.\d+)?/)
    let multiplier = 1
    if (lead) {
      multiplier = Number(lead[0])
      pos = lead[0].length
    }
    const { map, end } = parseGroup(part, pos, null, bySymbol)
    if (end !== part.length) throw new ChemError(`Unexpected '${part[end]}' at position ${end + 1}`)
    for (const [sym, n] of map) counts.set(sym, (counts.get(sym) || 0) + n * multiplier)
  }
  if (!counts.size) throw new ChemError("No elements found")
  return { counts, charge }
}

const CLOSE = { "(": ")", "[": "]", "{": "}" }

// "·", "*" and "•" always separate hydrate/adduct parts. A plain "." is
// ambiguous ("CuSO4.5H2O" vs "Li0.5CoO2"): it is a decimal point only when it
// follows a standalone "0", otherwise a hydrate separator.
function splitHydrate(src) {
  const parts = []
  let start = 0
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]
    const decimal = ch === "." && src[i - 1] === "0" && !/[\d.]/.test(src[i - 2] || "") && /\d/.test(src[i + 1] || "")
    if ("·*•".includes(ch) || (ch === "." && !decimal)) {
      parts.push(src.slice(start, i))
      start = i + 1
    }
  }
  parts.push(src.slice(start))
  return parts
}

function readNumber(str, pos) {
  const m = str.slice(pos).match(/^\d+(\.\d+)?/)
  return m ? { value: Number(m[0]), end: pos + m[0].length } : { value: 1, end: pos }
}

function parseGroup(str, pos, closer, bySymbol) {
  const map = new Map()
  const add = (sym, n) => map.set(sym, (map.get(sym) || 0) + n)
  while (pos < str.length) {
    const ch = str[pos]
    if (ch === closer) return { map, end: pos }
    if (CLOSE[ch]) {
      const inner = parseGroup(str, pos + 1, CLOSE[ch], bySymbol)
      if (str[inner.end] !== CLOSE[ch]) throw new ChemError(`Missing '${CLOSE[ch]}'`)
      if (!inner.map.size) throw new ChemError("Empty brackets")
      const num = readNumber(str, inner.end + 1)
      for (const [sym, n] of inner.map) add(sym, n * num.value)
      pos = num.end
      continue
    }
    if (/[A-Z]/.test(ch)) {
      let sym = ch
      if (/[a-z]/.test(str[pos + 1] || "")) sym += str[pos + 1]
      // Prefer the two-letter symbol only when it exists (e.g. "Co" vs "CO").
      if (sym.length === 2 && bySymbol && !bySymbol.has(sym)) sym = ch
      if (bySymbol && !bySymbol.has(sym)) throw new ChemError(`Unknown element '${sym}' at position ${pos + 1}`)
      const num = readNumber(str, pos + sym.length)
      add(sym, num.value)
      pos = num.end
      continue
    }
    if (Object.values(CLOSE).includes(ch)) throw new ChemError(`Unmatched '${ch}' at position ${pos + 1}`)
    throw new ChemError(`Unexpected '${ch}' at position ${pos + 1}`)
  }
  if (closer) throw new ChemError(`Missing '${closer}'`)
  return { map, end: pos }
}

// ── Formatting ─────────────────────────────────────────────────────────
export function fmtCount(n) {
  if (Math.abs(n - Math.round(n)) < 1e-9) return String(Math.round(n))
  return String(Number(n.toFixed(4)))
}

// Hill system: C first, then H, then alphabetical; without carbon, all alphabetical.
export function hillFormula(counts) {
  const syms = [...counts.keys()]
  const hasC = counts.has("C")
  const ordered = hasC
    ? ["C", ...(counts.has("H") ? ["H"] : []), ...syms.filter((s) => s !== "C" && s !== "H").sort()]
    : syms.sort()
  return ordered.map((s) => s + (counts.get(s) === 1 ? "" : fmtCount(counts.get(s)))).join("")
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
}

// HTML with <sub> counts and <sup> charges; leading hydrate coefficients stay inline.
export function formulaHTML(formula) {
  let src = escapeHtml(formula)
  let charge = ""
  const cm = src.match(/\^(\d*[+-]\d*)$/)
  if (cm) {
    charge = `<sup>${cm[1].replace("-", "−")}</sup>`
    src = src.slice(0, cm.index)
  }
  const body = src.replace(/([A-Za-z)\]}])(\d+(?:\.\d+)?)/g, "$1<sub>$2</sub>")
  return body + charge
}

// ── Mass & composition ─────────────────────────────────────────────────
export function molarMass(counts, bySymbol) {
  let mass = 0
  let variance = 0
  let approximate = false
  for (const [sym, n] of counts) {
    const el = bySymbol.get(sym)
    if (!el) throw new ChemError(`Unknown element '${sym}'`)
    const w = weightOf(el)
    if (w == null) throw new ChemError(`No atomic weight for ${sym}`)
    mass += n * w
    const u = el.atomicWeightUncertainty
    if (u != null) variance += (n * u) ** 2
    if (el.massApprox || el.atomicWeightBracketed) approximate = true
  }
  return { mass, uncertainty: Math.sqrt(variance), approximate }
}

export function composition(counts, bySymbol) {
  const { mass } = molarMass(counts, bySymbol)
  const atoms = [...counts.values()].reduce((a, b) => a + b, 0)
  return [...counts.entries()].map(([symbol, count]) => {
    const part = count * weightOf(bySymbol.get(symbol))
    return { symbol, count, mass: part, massPct: (part / mass) * 100, molePct: (count / atoms) * 100 }
  })
}

// Empirical formula from mass percentages: moles ∝ pct / weight, normalise to
// the smallest, then find the lowest multiplier giving near-integers.
export function empiricalFromPercent(percentBySymbol, bySymbol, { tolerance = 0.08, maxMultiplier = 12 } = {}) {
  const entries = Object.entries(percentBySymbol).filter(([, pct]) => pct > 0)
  if (!entries.length) throw new ChemError("Enter at least one percentage")
  const moles = entries.map(([sym, pct]) => {
    const el = bySymbol.get(sym)
    if (!el) throw new ChemError(`Unknown element '${sym}'`)
    return [sym, pct / weightOf(el)]
  })
  const min = Math.min(...moles.map(([, m]) => m))
  const ratios = moles.map(([sym, m]) => [sym, m / min])
  for (let k = 1; k <= maxMultiplier; k++) {
    if (ratios.every(([, r]) => Math.abs(r * k - Math.round(r * k)) <= tolerance * Math.max(1, k / 2))) {
      const counts = new Map(ratios.map(([sym, r]) => [sym, Math.round(r * k)]))
      return { counts, multiplier: k, ratios: Object.fromEntries(ratios) }
    }
  }
  const counts = new Map(ratios.map(([sym, r]) => [sym, Math.round(r * maxMultiplier)]))
  return { counts, multiplier: maxMultiplier, ratios: Object.fromEntries(ratios), approximate: true }
}

// ── Equation balancing (exact rational nullspace) ──────────────────────
function gcd(a, b) {
  a = a < 0n ? -a : a
  b = b < 0n ? -b : b
  while (b) [a, b] = [b, a % b]
  return a
}

class Frac {
  constructor(n, d = 1n) {
    if (d === 0n) throw new ChemError("Division by zero")
    if (d < 0n) { n = -n; d = -d }
    const g = gcd(n, d) || 1n
    this.n = n / g
    this.d = d / g
  }
  sub(o) { return new Frac(this.n * o.d - o.n * this.d, this.d * o.d) }
  mul(o) { return new Frac(this.n * o.n, this.d * o.d) }
  div(o) { return new Frac(this.n * o.d, this.d * o.n) }
  isZero() { return this.n === 0n }
}

const ARROW = /\s*(?:<=>|<->|⇌|→|⟶|->|=>|=)\s*/

export function splitEquation(equation) {
  const sides = equation.split(ARROW)
  if (sides.length !== 2) throw new ChemError("Use one arrow, e.g. Fe + O2 -> Fe2O3")
  const species = (side) =>
    side
      .split(/\s+\+\s+|\s*\+\s*(?=\d*\s*(?:[A-Z(\[{]|e\b))/)
      .map((s) => s.trim())
      .filter(Boolean)
      .map((s) => s.replace(/^\d+(?=\s*(?:[A-Z(\[{]|e\b))/, "").trim())
  const reactants = species(sides[0])
  const products = species(sides[1])
  if (!reactants.length || !products.length) throw new ChemError("Both sides need at least one species")
  return { reactants, products }
}

// Returns smallest positive integer coefficients, or throws when the system
// has no solution or more than one independent solution.
export function balanceEquation(equation, bySymbol) {
  const { reactants, products } = splitEquation(equation)
  const all = [...reactants, ...products]
  // "e" / "e^-" is a free electron (half-reactions): no atoms, charge −1.
  const parsed = all.map((f) => (/^e(\^?-)?$/.test(f) ? { counts: new Map(), charge: -1 } : parseFormula(f, bySymbol)))
  const rows = [...new Set(parsed.flatMap((p) => [...p.counts.keys()]))]
  const useCharge = parsed.some((p) => p.charge !== 0)

  const toFrac = (x) => {
    // Formula counts may be decimals (≤4 places); scale into an exact fraction.
    const scaled = Math.round(x * 10000)
    return new Frac(BigInt(scaled), 10000n)
  }
  const matrix = rows.map((sym) =>
    parsed.map((p, j) => {
      const v = toFrac(p.counts.get(sym) || 0)
      return j < reactants.length ? v : new Frac(-v.n, v.d)
    })
  )
  if (useCharge) {
    matrix.push(parsed.map((p, j) => new Frac(BigInt(j < reactants.length ? p.charge : -p.charge))))
  }

  const cols = all.length
  const m = matrix.map((r) => r.slice())
  const pivots = []
  let r = 0
  for (let c = 0; c < cols && r < m.length; c++) {
    const pr = m.findIndex((row, i) => i >= r && !row[c].isZero())
    if (pr === -1) continue
    ;[m[r], m[pr]] = [m[pr], m[r]]
    const pv = m[r][c]
    m[r] = m[r].map((x) => x.div(pv))
    for (let i = 0; i < m.length; i++) {
      if (i !== r && !m[i][c].isZero()) {
        const f = m[i][c]
        m[i] = m[i].map((x, k) => x.sub(f.mul(m[r][k])))
      }
    }
    pivots.push(c)
    r++
  }
  const free = [...Array(cols).keys()].filter((c) => !pivots.includes(c))
  if (free.length === 0) throw new ChemError("No balanced solution — check the formulas")
  if (free.length > 1) {
    throw new ChemError(`Underdetermined: ${free.length} independent reactions combine here — split it into separate equations`)
  }
  const f = free[0]
  const sol = Array(cols).fill(null)
  sol[f] = new Frac(1n)
  pivots.forEach((c, i) => { sol[c] = new Frac(-m[i][f].n, m[i][f].d) })

  let lcm = 1n
  for (const x of sol) lcm = (lcm * x.d) / gcd(lcm, x.d)
  let ints = sol.map((x) => (x.n * lcm) / x.d)
  if (ints.every((x) => x <= 0n)) ints = ints.map((x) => -x)
  if (ints.some((x) => x <= 0n)) throw new ChemError("Cannot balance with all species on the sides given — a species may belong on the other side")
  const g = ints.reduce((a, b) => gcd(a, b))
  ints = ints.map((x) => x / g)

  const coeffs = ints.map(Number)
  const species = all.map((formula, i) => ({
    formula,
    coefficient: coeffs[i],
    side: i < reactants.length ? "reactant" : "product",
    molarMass: parsed[i].counts.size ? molarMass(parsed[i].counts, bySymbol).mass : 0,
    charge: parsed[i].charge
  }))
  return { species, text: formatEquation(species) }
}

export function formatEquation(species) {
  const side = (s) => species.filter((x) => x.side === s).map((x) => `${x.coefficient === 1 ? "" : x.coefficient}${x.formula}`).join(" + ")
  return `${side("reactant")} → ${side("product")}`
}

// Stoichiometry over a balanced equation. `given` maps species index → grams.
// Limiting reagent = smallest (moles / coefficient) among given reactants.
export function stoichiometry(species, given) {
  const entries = Object.entries(given).filter(([, g]) => Number.isFinite(g) && g > 0)
  if (!entries.length) return null
  let extent = Infinity
  let limiting = null
  for (const [idx, grams] of entries) {
    const s = species[idx]
    const ext = grams / s.molarMass / s.coefficient
    if (ext < extent) { extent = ext; limiting = Number(idx) }
  }
  return {
    extent,
    limiting,
    rows: species.map((s) => ({ ...s, moles: extent * s.coefficient, grams: extent * s.coefficient * s.molarMass }))
  }
}

// ── Charge-balanced compound prediction & naming ───────────────────────
const NUM_PREFIX = ["", "mono", "di", "tri", "tetra", "penta", "hexa", "hepta", "octa", "nona", "deca"]
const ANION_ROOT = {
  H: "hydride", B: "boride", C: "carbide", N: "nitride", O: "oxide", F: "fluoride", Si: "silicide", P: "phosphide",
  S: "sulfide", Cl: "chloride", Ge: "germanide", As: "arsenide", Se: "selenide", Br: "bromide", Sb: "antimonide",
  Te: "telluride", I: "iodide", At: "astatide", Bi: "bismuthide", Po: "polonide", Sn: "stannide", Pb: "plumbide"
}
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

export function isMetal(el) {
  return !["reactive-nonmetal", "noble-gas", "metalloid"].includes(el.category) && !(el.category === "unknown" && el.group >= 17)
}

export function bondCharacter(a, b) {
  const ea = a.electronegativity
  const eb = b.electronegativity
  if (isMetal(a) && isMetal(b)) return { kind: "metallic", delta: ea != null && eb != null ? Math.abs(ea - eb) : null, ionicPct: null }
  if (ea == null || eb == null) return { kind: "unknown", delta: null, ionicPct: null }
  const delta = Math.abs(ea - eb)
  const ionicPct = 100 * (1 - Math.exp(-0.25 * delta * delta)) // Pauling's estimate
  const kind = delta < 0.4 ? "nonpolar covalent" : delta < 1.7 ? "polar covalent" : "ionic"
  return { kind, delta, ionicPct }
}

const iGcd = (a, b) => (b ? iGcd(b, a % b) : Math.abs(a))

// For two elements: the more electronegative one takes its negative states,
// the other its positive states; x·(+p) = y·|n| gives AxBy (reduced).
export function predictBinaries(a, b, { includeRare = false } = {}) {
  if (!a || !b || a.symbol === b.symbol) return []
  const enA = a.electronegativity ?? 0
  const enB = b.electronegativity ?? 0
  const [pos, neg] = enA <= enB ? [a, b] : [b, a]
  const states = (el, sign) => {
    const main = el.oxidationMain?.length ? el.oxidationMain : el.oxidationStates || []
    const pool = includeRare ? [...new Set([...(el.oxidationStates || []), ...main])] : main
    return pool.filter((s) => (sign > 0 ? s > 0 : s < 0))
  }
  const posStates = states(pos, 1)
  let negStates = states(neg, -1)
  if (!negStates.length && (neg.oxidationStates || []).some((s) => s < 0)) negStates = (neg.oxidationStates || []).filter((s) => s < 0)
  const out = []
  for (const p of posStates) {
    for (const n of negStates) {
      const g = iGcd(p, -n)
      const x = -n / g
      const y = p / g
      const formula = `${pos.symbol}${x === 1 ? "" : x}${neg.symbol}${y === 1 ? "" : y}`
      out.push({ formula, cation: pos.symbol, anion: neg.symbol, cationState: p, anionState: n, x, y, name: nameBinary(pos, neg, x, y, p, posStates.length > 1) })
    }
  }
  const seen = new Set()
  return out.filter((c) => !seen.has(c.formula) && seen.add(c.formula))
}

export function nameBinary(pos, neg, x, y, posState, multipleStates) {
  const root = ANION_ROOT[neg.symbol] || `${neg.name.toLowerCase()}ide`
  if (isMetal(pos)) {
    const roman = multipleStates && ROMAN[posState] ? `(${ROMAN[posState]})` : ""
    return `${pos.name.toLowerCase()}${roman} ${root}`
  }
  // Molecular binary: Greek prefixes, "mono" dropped on the first element, and
  // "mono-o"/"a-o" elision before oxide (monoxide, pentoxide).
  const first = `${x > 1 ? NUM_PREFIX[x] || `${x}-` : ""}${pos.name.toLowerCase()}`
  let prefix = NUM_PREFIX[y] || `${y}-`
  if (root.startsWith("o") && /[ao]$/.test(prefix)) prefix = prefix.slice(0, -1)
  return `${first} ${prefix}${root}`
}

// ── Alloy design ───────────────────────────────────────────────────────
export function normalise(map) {
  const total = Object.values(map).reduce((a, b) => a + (b > 0 ? b : 0), 0)
  if (total <= 0) return {}
  return Object.fromEntries(Object.entries(map).filter(([, v]) => v > 0).map(([k, v]) => [k, (v / total) * 100]))
}

export function wtToAt(wt, bySymbol) {
  const moles = Object.fromEntries(Object.entries(normalise(wt)).map(([s, w]) => [s, w / weightOf(bySymbol.get(s))]))
  return normalise(moles)
}

export function atToWt(at, bySymbol) {
  const mass = Object.fromEntries(Object.entries(normalise(at)).map(([s, x]) => [s, x * weightOf(bySymbol.get(s))]))
  return normalise(mass)
}

// Valence electron concentration per atom, as used in HEA phase rules
// (Guo et al.): d-block = group number; s/p-block = outer s+p electrons.
export function vecOf(el) {
  if (el.group == null) return el.block === "f" ? 3 : null
  if (el.group <= 12) return el.group
  return el.group - 10
}

export function alloyMetrics(atPct, bySymbol) {
  const x = Object.fromEntries(Object.entries(normalise(atPct)).map(([s, v]) => [s, v / 100]))
  const syms = Object.keys(x)
  const els = syms.map((s) => bySymbol.get(s))
  const mean = (f) => {
    let sum = 0
    let used = 0
    syms.forEach((s, i) => {
      const v = f(els[i])
      if (v != null && Number.isFinite(v)) { sum += x[s] * v; used += x[s] }
    })
    return used > 0.999 ? sum : null
  }
  const deltaSmix = -R_GAS * syms.reduce((acc, s) => acc + (x[s] > 0 ? x[s] * Math.log(x[s]) : 0), 0)
  const radius = (el) => el.metallicRadius ?? el.atomicRadius ?? null
  const rBar = mean(radius)
  const delta = rBar ? 100 * Math.sqrt(syms.reduce((acc, s, i) => acc + x[s] * (1 - radius(els[i]) / rBar) ** 2, 0)) : null
  const enBar = mean((el) => el.electronegativity)
  const deltaChi = enBar != null ? Math.sqrt(syms.reduce((acc, s, i) => acc + x[s] * (els[i].electronegativity - enBar) ** 2, 0)) : null
  const vec = mean(vecOf)
  const tm = mean((el) => el.melt)

  // Ideal-mixing density: 1/ρ = Σ wᵢ/ρᵢ (weight fractions).
  const wt = atToWt(atPct, bySymbol)
  let invRho = 0
  let densityOk = true
  for (const [s, w] of Object.entries(wt)) {
    const el = bySymbol.get(s)
    if (!el.density || el.densityUnit === "g/L") { densityOk = false; break }
    invRho += w / 100 / el.density
  }
  const density = densityOk && invRho > 0 ? 1 / invRho : null
  const weight = mean(weightOf)

  let phase = null
  if (vec != null) phase = vec >= 8 ? "FCC solid solution favoured" : vec < 6.87 ? "BCC solid solution favoured" : "FCC + BCC mixture expected"
  const solidSolution = delta != null ? (delta <= 6.6 ? "Size mismatch permits a solid solution (δ ≤ 6.6%)" : "Large size mismatch — intermetallics/amorphous phases likely (δ > 6.6%)") : null

  return {
    components: syms.length,
    deltaSmix,
    deltaSmixR: deltaSmix / R_GAS,
    entropyClass: deltaSmix / R_GAS >= 1.5 ? "high-entropy" : deltaSmix / R_GAS >= 1 ? "medium-entropy" : "low-entropy",
    delta,
    rBar,
    enBar,
    deltaChi,
    vec,
    meltRuleOfMixtures: tm,
    density,
    meanAtomicWeight: weight,
    phase,
    solidSolution
  }
}

// Hume-Rothery rules for extensive substitutional solid solubility of
// `solute` in `solvent`.
export function humeRothery(solvent, solute) {
  const r1 = solvent.metallicRadius ?? solvent.atomicRadius
  const r2 = solute.metallicRadius ?? solute.atomicRadius
  const sizeDiff = r1 && r2 ? (Math.abs(r2 - r1) / r1) * 100 : null
  const sameLattice = solvent.latticeStructure && solute.latticeStructure ? solvent.latticeStructure === solute.latticeStructure : null
  const dEN = solvent.electronegativity != null && solute.electronegativity != null ? Math.abs(solvent.electronegativity - solute.electronegativity) : null
  // Chemical valence: lowest common positive oxidation state (Cu 1, Ni 2, Zn 2).
  const valence = (el) => {
    const pos = (el.oxidationMain?.length ? el.oxidationMain : el.oxidationStates || []).filter((s) => s > 0)
    return pos.length ? Math.min(...pos) : null
  }
  const v1 = valence(solvent)
  const v2 = valence(solute)
  const rules = [
    { key: "size", label: "Atomic size difference < 15%", value: sizeDiff, pass: sizeDiff == null ? null : sizeDiff < 15, detail: sizeDiff == null ? "radius unknown" : `${sizeDiff.toFixed(1)}%` },
    { key: "structure", label: "Same crystal structure", value: sameLattice, pass: sameLattice, detail: `${solvent.latticeStructure || "?"} vs ${solute.latticeStructure || "?"}` },
    { key: "en", label: "Similar electronegativity (Δχ < 0.4)", value: dEN, pass: dEN == null ? null : dEN < 0.4, detail: dEN == null ? "χ unknown" : `Δχ = ${dEN.toFixed(2)}` },
    { key: "valence", label: "Solute valence ≥ solvent valence (or equal)", value: [v1, v2], pass: v1 == null || v2 == null ? null : v2 >= v1, detail: `+${v1 ?? "?"} → +${v2 ?? "?"}` }
  ]
  const passed = rules.filter((r) => r.pass === true).length
  const verdict = passed === 4 ? "Extensive solid solubility likely" : passed >= 3 && rules[0].pass ? "Appreciable solubility possible" : rules[0].pass === false ? "Limited solubility — size factor fails" : "Limited solubility expected"
  return { rules, passed, verdict }
}

// ── Numbers ────────────────────────────────────────────────────────────
export function sig(v, digits = 4) {
  if (v == null || !Number.isFinite(v)) return "—"
  if (v === 0) return "0"
  const abs = Math.abs(v)
  if (abs >= 1e6 || abs < 1e-3) return v.toExponential(digits - 1).replace("e+", "e")
  return String(Number(v.toPrecision(digits)))
}
