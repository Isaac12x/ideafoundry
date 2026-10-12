// Detail panel: renders the "Specimen Atlas" side panel for a selected
// element and wires up its internal tabs + nav/close/tray events.
//
// Dependencies are imported by importmap bare specifier, which only resolves
// in the browser. `renderDetailWith` takes them as a parameter so the render
// logic stays testable outside the browser; `renderDetail`/`wireDetail` are
// what the app calls.
import * as electronsMod from "lib/periodic_table/electrons";
import * as chemMod from "lib/periodic_table/chem";
import * as trendsMod from "lib/periodic_table/trends";
import { COMPOUNDS, FORMULA_ALIASES, ALLOYS } from "lib/periodic_table/compounds";

const SUPER = { 0: "⁰", 1: "¹", 2: "²", 3: "³", 4: "⁴", 5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹" };

function toSuperscript(config) {
  return config.replace(/(\d+)([spdf])(\d+)/g, (_, n, l, e) => `${n}${l}${[...e].map((d) => SUPER[d] ?? d).join("")}`);
}

function fmtNum(v, precision = 4) {
  if (v == null || !Number.isFinite(v)) return "—";
  return String(Number(v.toPrecision(precision)));
}

function ordinal(n) {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

export function formatTemp(tempK, unit = "K") {
  if (tempK == null || !Number.isFinite(tempK)) return "—";
  if (unit === "C") return `${Math.round((tempK - 273.15) * 10) / 10} °C`;
  if (unit === "F") return `${Math.round((((tempK - 273.15) * 9) / 5 + 32) * 10) / 10} °F`;
  return `${Number(tempK.toPrecision(6))} K`;
}

const DECAY_MODES = {
  "B-": "β⁻ (neutron → proton + electron)",
  "B+": "β⁺ (positron emission)",
  EC: "electron capture",
  "EC+B+": "electron capture / β⁺",
  A: "α (helium-4 nucleus)",
  SF: "spontaneous fission",
  IT: "isomeric transition",
  P: "proton emission",
  "2P": "two-proton emission",
  N: "neutron emission",
  "2N": "two-neutron emission",
  "B-N": "β⁻ delayed neutron",
  "B-2N": "β⁻ delayed two neutrons",
  "2B-": "double β⁻",
  "2EC": "double electron capture",
  "2B+": "double β⁺",
  "B+P": "β⁺ delayed proton",
  ECP: "EC delayed proton",
  "B-A": "β⁻ delayed α",
  ECSF: "EC delayed fission"
};

const GLOSS = {
  "Term symbol": "Spectroscopic ground state ²ˢ⁺¹L_J: multiplicity (unpaired spins), orbital angular momentum (S P D F…), total J.",
  "Valence electrons": "Outer electrons that take part in bonding.",
  Polarisability: "Ease of distorting the electron cloud (atomic units; 1 a.u. ≈ 0.148 Å³).",
  "Specific heat": "Heat to raise 1 g by 1 K.",
  "Thermal expansion": "Fractional length change per kelvin.",
  "Poisson's ratio": "Transverse contraction ÷ axial strain.",
  Resistivity: "Resistance of a 1 m cube; conductivity is its inverse.",
  "Supply risk": "RSC/BGS relative index, 1 (low) to 10 (high)."
};

// "5D4" → ⁵D₄; jj-coupled values such as "(1/2,1/2)0" are shown as given.
export function termSymbolHTML(esc, term) {
  const m = /^(\d+)([SPDFGHIKLMN])(\d+(?:\/\d+)?)\*?$/.exec(term || "");
  return m ? `<sup>${m[1]}</sup>${m[2]}<sub>${m[3]}</sub>` : esc(term || "");
}

function row(label, value, hint) {
  if (value == null || value === "" || value === "—") return "";
  const tip = hint ?? GLOSS[label];
  return `<div class="ptd-row"><dt${tip ? ` title="${tip.replace(/"/g, "&quot;")}"` : ""}>${label}${tip ? '<span class="ptd-q" aria-hidden="true">?</span>' : ""}</dt><dd>${value}</dd></div>`;
}

const section = (title, body, note = "") =>
  body && body.replace(/<[^>]+>/g, "").trim() ? `<section class="ptd-section"><h4 class="ptd-subhead">${title}</h4>${note ? `<p class="ptd-note">${note}</p>` : ""}${body}</section>` : "";

const unitVal = (v, unit, digits = 4) => (v == null || !Number.isFinite(v) ? null : `${fmtNum(v, digits)}${unit ? ` ${unit}` : ""}`);

function sci(v, unit) {
  return v == null ? null : trendsMod.formatValue(v, unit);
}

// ── Atom tab pieces ───────────────────────────────────────────────────
function ionizationStrip(esc, values) {
  if (!values || !values.length) return "";
  const logs = values.map((v) => Math.log10(Math.max(v, 1)));
  const maxLog = Math.max(...logs, 0.0001);
  // Biggest successive ratio marks the break into a filled inner shell.
  let jump = -1;
  let best = 0;
  for (let i = 1; i < values.length; i++) {
    const r = values[i] / values[i - 1];
    if (r > best) { best = r; jump = i; }
  }
  const bars = values
    .map((v, i) => {
      const pct = Math.max(3, (logs[i] / maxLog) * 100);
      return (
        `<div class="ptd-ie-bar${i === jump ? " is-jump" : ""}">` +
        `<span class="ptd-ie-label">${esc(ordinal(i + 1))}</span>` +
        `<span class="ptd-ie-track"><span class="ptd-ie-fill" style="width:${pct.toFixed(1)}%"></span></span>` +
        `<span class="ptd-ie-value">${esc(fmtNum(v, 5))} eV</span>` +
        `</div>`
      );
    })
    .join("");
  const note = jump > 0 && best > 1.8
    ? `Largest jump between the ${ordinal(jump)} and ${ordinal(jump + 1)} ionisations (×${best.toFixed(1)}): ${jump} electron${jump > 1 ? "s" : ""} sit outside a stable core.`
    : "";
  return section("Successive ionisation energies", `<div class="ptd-ionization">${bars}</div>`, note);
}

function radiiBars(el) {
  const radii = [
    ["Atomic (empirical)", el.atomicRadius],
    ["Calculated (Rahm)", el.atomicRadiusCalc],
    ["Covalent, single (Cordero)", el.covalentRadius],
    ["Covalent, double (Pyykkö)", el.covalentRadiusPyykko?.[1]],
    ["Covalent, triple (Pyykkö)", el.covalentRadiusPyykko?.[2]],
    ["Metallic (CN 12)", el.metallicRadius],
    ["Van der Waals", el.vdwRadius]
  ].filter(([, v]) => v != null);
  if (!radii.length) return "";
  const max = 350;
  return section(
    "Radii",
    `<div class="ptd-bars">${radii
      .map(([label, v]) => `<div class="ptd-bar"><span>${label}</span><span class="ptd-bar-track"><span style="width:${Math.min(100, (v / max) * 100)}%"></span></span><b>${fmtNum(v, 4)} pm</b></div>`)
      .join("")}</div>`,
    "Different measurements answer different questions: bond length (covalent), packing in metals (metallic), and non-bonded contact (van der Waals)."
  );
}

// ── Ions tab ──────────────────────────────────────────────────────────
function oxidationLine(el) {
  const all = new Set(el.oxidationStates || []);
  const main = new Set(el.oxidationMain || []);
  const icsd = new Set(el.oxidationIcsd || []);
  if (!all.size && !main.size) return "";
  const ticks = [];
  for (let i = -5; i <= 9; i++) {
    const cls = main.has(i) ? " is-main" : all.has(i) ? " is-active" : "";
    const label = i > 0 ? `+${i}` : `${i}`;
    ticks.push(`<span class="ptd-ox-tick${cls}${icsd.has(i) ? " is-icsd" : ""}" title="${label}${main.has(i) ? " · main" : all.has(i) ? " · observed" : ""}${icsd.has(i) ? " · in ICSD crystal structures" : ""}">${all.has(i) || main.has(i) ? label : ""}</span>`);
  }
  return section(
    "Oxidation states",
    `<div class="ptd-ox-line">${ticks.join("")}</div><p class="ptd-legend-inline"><span class="k k-main"></span>common <span class="k k-other"></span>known <span class="k k-icsd"></span>seen in crystal structures (ICSD)</p>`
  );
}

function shannonTable(esc, rows) {
  if (!rows?.length) return section("Shannon ionic radii", `<p class="ptd-empty">No tabulated ionic radii.</p>`);
  const body = rows
    .map(([charge, cn, spin, crystal, ionic, reliable]) =>
      `<tr${reliable ? ' class="is-reliable"' : ""}><td>${charge > 0 ? "+" : ""}${charge}</td><td>${esc(cn)}</td><td>${spin ? esc(spin) : ""}</td><td>${fmtNum(ionic, 4)}</td><td>${fmtNum(crystal, 4)}</td></tr>`)
    .join("");
  return section(
    "Shannon ionic radii",
    `<div class="ptd-table-wrap"><table class="ptd-table"><thead><tr><th>Charge</th><th>CN</th><th>Spin</th><th>Ionic r / pm</th><th>Crystal r / pm</th></tr></thead><tbody>${body}</tbody></table></div>`,
    "Shannon (1976). Radius depends on charge, coordination number (CN, Roman numerals) and spin state (HS/LS). Bold rows are the most reliable values. Use ionic radii with O²⁻ = 140 pm; crystal radii with O²⁻ = 126 pm."
  );
}

// ── Isotopes tab ──────────────────────────────────────────────────────
function isotopesSection(esc, el, details) {
  const isotopes = details.isotopes || [];
  if (!isotopes.length) return `<p class="ptd-empty">No isotope data.</p>`;
  const natural = isotopes.filter((i) => (i.abundance || 0) > 0);
  const compBar = natural.length
    ? `<div class="ptd-composition" role="img" aria-label="Natural isotopic composition">${natural
        .map((i, k) => `<span class="ptd-composition-seg" style="width:${(i.abundance || 0).toFixed(3)}%;--k:${k}" title="${esc(el.symbol)}-${i.mass}: ${fmtNum(i.abundance, 5)}%"><b>${i.abundance > 8 ? `${el.symbol}-${i.mass}` : ""}</b></span>`)
        .join("")}</div>`
    : `<p class="ptd-note">No naturally occurring isotopes${el.radioactive ? " — every atom on Earth was made in a reactor or accelerator, or is a transient decay product" : ""}.</p>`;
  const rows = isotopes
    .map((iso) => {
      const mode = iso.decay ? `<abbr title="${esc(DECAY_MODES[iso.decay] || iso.decay)}">${esc(iso.decay)}</abbr>` : "";
      const life = iso.stable ? "stable" : iso.halfLifeHuman || iso.halfLife || "—";
      return (
        `<tr class="${iso.stable ? "is-stable" : "is-radioactive"}">` +
        `<td><sup>${iso.mass}</sup>${esc(el.symbol)}</td>` +
        `<td>${iso.exactMass != null ? iso.exactMass.toFixed(6) : "—"}</td>` +
        `<td>${iso.abundance ? `${fmtNum(iso.abundance, 5)}%` : ""}</td>` +
        `<td>${esc(life)}</td>` +
        `<td>${mode}</td>` +
        `<td>${iso.spin ? esc(iso.spin) : ""}</td>` +
        `</tr>`
      );
    })
    .join("");
  return (
    compBar +
    `<div class="ptd-table-wrap"><table class="ptd-table ptd-table--iso"><thead><tr><th>Nuclide</th><th>Mass / u</th><th>Natural</th><th>Half-life</th><th>Decay</th><th>Jπ</th></tr></thead><tbody>${rows}</tbody></table></div>` +
    `<p class="ptd-note">${el.isotopesKnown ?? isotopes.length} nuclides known for ${esc(el.name)}; listed: all natural isotopes and the longest-lived others. Source: IAEA Live Chart of Nuclides.</p>` +
    `<button type="button" class="ptd-link-btn" data-action="bench" data-tab="nuclides" data-z="${el.number}">Show ${esc(el.symbol)} on the chart of nuclides →</button>` +
    (details.nuclearNote ? section("Nuclear technology", `<p class="ptd-nuclear-note">${esc(details.nuclearNote)}</p>`) : "")
  );
}

// ── Compounds tab ─────────────────────────────────────────────────────
const PARTNERS = ["H", "O", "F", "Cl", "S", "N", "C"];

function compoundsSection(esc, chem, el, elements) {
  const bySymbol = new Map(elements.map((e) => [e.symbol, e]));
  const predicted = [];
  for (const partner of PARTNERS) {
    if (partner === el.symbol) continue;
    const other = bySymbol.get(partner);
    for (const c of chem.predictBinaries(el, other)) predicted.push({ ...c, partner: other });
  }
  const known = new Map();
  for (const [formula, name, cls, note] of COMPOUNDS) {
    try {
      const { counts } = chem.parseFormula(FORMULA_ALIASES[formula] ?? formula, bySymbol);
      if (counts.has(el.symbol)) known.set(chem.hillFormula(counts), { formula, name, cls, note, counts });
    } catch {
      // curated rows are validated in tests; skip anything unparsable defensively
    }
  }
  // Catalogued (experimentally known) formulas first, then pure predictions.
  const scored = predicted.map((c) => {
    const { counts } = chem.parseFormula(c.formula, bySymbol);
    return { ...c, counts, isKnown: known.has(chem.hillFormula(counts)) };
  });
  scored.sort((a, b) => Number(b.isKnown) - Number(a.isKnown));
  const predictedRows = scored
    .slice(0, 18)
    .map((c) => {
      const { counts, isKnown } = c;
      const mm = chem.molarMass(counts, bySymbol).mass;
      const bond = chem.bondCharacter(el, c.partner);
      return `<tr><td class="ptd-formula">${chem.formulaHTML(c.formula)}</td><td>${esc(c.name)}</td><td>${c.cationState > 0 ? "+" : ""}${c.cationState} / ${c.anionState}</td><td>${fmtNum(mm, 5)}</td><td>${esc(bond.kind)}${bond.ionicPct != null ? ` · ${Math.round(bond.ionicPct)}% ionic` : ""}</td><td>${isKnown ? '<span class="ptd-tag">catalogued</span>' : ""}</td></tr>`;
    })
    .join("");
  const knownRows = [...known.values()]
    .slice(0, 40)
    .map((k) => `<li><button type="button" class="ptd-compound" data-action="formula" data-formula="${esc(FORMULA_ALIASES[k.formula] ?? k.formula)}"><span class="ptd-formula">${chem.formulaHTML(k.formula)}</span><span>${esc(k.name)}</span></button><small>${esc(k.note)}</small></li>`)
    .join("");
  const alloys = ALLOYS.filter(([, comp]) => comp[el.symbol] != null)
    .map(([name, comp]) => `<li><b>${esc(name)}</b> <small>${fmtNum(comp[el.symbol], 3)} wt% ${esc(el.symbol)}</small></li>`)
    .join("");
  return (
    section(
      "Predicted binary compounds",
      predictedRows
        ? `<div class="ptd-table-wrap"><table class="ptd-table"><thead><tr><th>Formula</th><th>Name</th><th>Ox. states</th><th>M / g·mol⁻¹</th><th>Bond</th><th></th></tr></thead><tbody>${predictedRows}</tbody></table></div>`
        : `<p class="ptd-empty">No charge-balanced binaries from common oxidation states${el.category === "noble-gas" ? " — a noble gas" : ""}.</p>`,
      "Built by balancing common oxidation states (x·cation = y·|anion|). Bond character from Pauling electronegativity difference. Prediction is a starting point — real chemistry adds kinetics, lattice energy and covalency."
    ) +
    section("Reference compounds & minerals", knownRows ? `<ul class="ptd-compounds">${knownRows}</ul>` : "", "Click a compound to load it into the Formula bench.") +
    section("Engineering alloys containing it", alloys ? `<ul class="ptd-alloys">${alloys}</ul>` : "")
  );
}

// ── Discovery tab ─────────────────────────────────────────────────────
const METHOD_LABEL = {
  ancient: "Known in antiquity", chemical: "Chemical isolation", mineral: "Mineral analysis", electrolysis: "Electrolysis",
  gas: "Gas chemistry / liquefied air", spectroscopy: "Optical spectroscopy", xray: "X-ray spectroscopy",
  radiochemistry: "Radiochemistry", synthesis: "Nuclear synthesis", debris: "Thermonuclear test debris"
};

function historySection(esc, el, details) {
  const year = el.ancient
    ? `Antiquity${el.earliestUse != null ? ` (earliest use c. ${el.earliestUse < 0 ? `${-el.earliestUse} BCE` : `${el.earliestUse} CE`})` : ""}`
    : el.yearDiscovered != null ? String(el.yearDiscovered) : "Unknown";
  const map = el.discoveryLat != null
    ? `<figure class="ptd-minimap" data-lat="${el.discoveryLat}" data-lon="${el.discoveryLon}"><svg viewBox="0 0 360 150" role="img" aria-label="Map pin at ${esc(el.discoveryPlace || "")}"><path class="ptd-land" d=""/><circle class="ptd-pin-halo" cx="${el.discoveryLon + 180}" cy="${90 - el.discoveryLat}" r="7"/><circle class="ptd-pin" cx="${el.discoveryLon + 180}" cy="${90 - el.discoveryLat}" r="2.6"/></svg><figcaption>${esc(el.discoveryPlace || "")}</figcaption></figure>`
    : "";
  return (
    map +
    `<dl class="ptd-deflist ptd-museum-label">` +
    row(el.ancient ? "Known since" : "Discovered", esc(year)) +
    row("By", el.discoveredBy ? esc(el.discoveredBy) : null) +
    row("Where", el.discoveryPlace ? esc(el.discoveryPlace) : null) +
    row("How", el.discoveryMethod ? esc(METHOD_LABEL[el.discoveryMethod] || el.discoveryMethod) : null) +
    row("Named by", details.namedBy ? esc(details.namedBy) : null) +
    row("Name origin", details.nameOrigin ? esc(details.nameOrigin) : null) +
    `</dl>` +
    (details.discoveryNote ? `<p class="ptd-story">${esc(details.discoveryNote)}</p>` : "") +
    `<button type="button" class="ptd-link-btn" data-action="bench" data-tab="map">Open the discovery map →</button>`
  );
}

// ── Earth & supply tab ────────────────────────────────────────────────
function rankOf(elements, key, el) {
  const vals = elements.filter((e) => e[key] != null).sort((a, b) => b[key] - a[key]);
  const i = vals.findIndex((e) => e.number === el.number);
  return i >= 0 ? `#${i + 1} of ${vals.length}` : null;
}

function earthSection(esc, el, details, elements) {
  const s = details.supply;
  const gauge = s?.risk != null
    ? `<div class="ptd-gauge" role="img" aria-label="Supply risk ${s.risk} of 10"><span class="ptd-gauge-fill" style="--v:${s.risk / 10}"></span><b>${fmtNum(s.risk, 2)}</b><small>/ 10 supply risk</small></div>`
    : "";
  const list = (items) => (items?.length ? `<ol class="ptd-rank">${items.map((x) => `<li>${esc(x)}</li>`).join("")}</ol>` : null);
  return (
    section(
      "Abundance",
      `<dl class="ptd-deflist">` +
        row("Earth's crust", el.abundanceCrust != null ? `${sci(el.abundanceCrust, "mg/kg")} <small>${rankOf(elements, "abundanceCrust", el) ?? ""}</small>` : null) +
        row("Seawater", el.abundanceSea != null ? `${sci(el.abundanceSea, "mg/L")} <small>${rankOf(elements, "abundanceSea", el) ?? ""}</small>` : null) +
        row("Goldschmidt class", el.goldschmidt ? esc(el.goldschmidt) : null) +
        row("Geochemical group", el.geochemicalClass ? esc(el.geochemicalClass) : null) +
        `</dl>`
    ) +
    section("Occurrence & production", details.occurrence ? `<p class="ptd-prose">${esc(details.occurrence)}</p>` : "") +
    section(
      "Supply chain",
      s
        ? gauge +
            `<dl class="ptd-deflist">` +
            row("Top producers", list(s.producers)) +
            row("Largest reserves", list(s.reserves)) +
            row("Price", s.pricePerKg != null ? `${sci(s.pricePerKg, "USD/kg")}` : null) +
            row("Recycling rate", s.recycling ? `${esc(s.recycling)}%` : null) +
            row("Substitutability", s.substitutability ? esc(s.substitutability) : null) +
            row("Production concentration", s.productionConcentration != null ? `${fmtNum(s.productionConcentration, 3)} (HHI, %)` : null) +
            `</dl>`
        : "",
      "RSC / British Geological Survey supply-risk data (snapshot; prices fluctuate)."
    )
  );
}

// ── Header ────────────────────────────────────────────────────────────
function headerPlate(esc, el, { categories, neighbours, tempK, unit, inTray }) {
  const categoryLabel = categories?.[el.category]?.label || el.category || "Unknown";
  const state = trendsMod.stateAt(el, tempK);
  const prev = neighbours?.prev;
  const next = neighbours?.next;
  const weight = el.atomicWeightBracketed
    ? `[${Math.round(el.mass)}]`
    : `${fmtNum(el.mass, 8)}${el.atomicWeightUncertainty ? `<small>±${fmtNum(el.atomicWeightUncertainty, 2)}</small>` : ""}`;
  return (
    `<header class="ptd-plate">` +
    `<button type="button" class="ptd-nav ptd-nav--prev" data-action="prev" ${prev ? `data-number="${prev}"` : "disabled"} aria-label="Previous element">‹</button>` +
    `<div class="ptd-plate-main">` +
    `<div class="ptd-plate-symbol">${esc(el.symbol)}</div>` +
    `<div class="ptd-plate-meta">` +
    `<span class="ptd-plate-number">${el.number}${el.cas ? ` · CAS ${esc(el.cas)}` : ""}</span>` +
    `<h2 class="ptd-plate-name">${esc(el.name)}</h2>` +
    `<span class="ptd-plate-mass">${weight} u</span>` +
    `<span class="ptd-chips"><span class="ptd-chip ptd-chip--category">${esc(categoryLabel)}</span>` +
    `<span class="ptd-chip ptd-chip--state">${esc(state)} at ${esc(formatTemp(tempK, unit))}</span>` +
    (el.radioactive ? `<span class="ptd-chip ptd-chip--hazard">radioactive</span>` : "") +
    `</span></div>` +
    `</div>` +
    `<div class="ptd-plate-actions">` +
    `<button type="button" class="ptd-tray-btn${inTray ? " is-on" : ""}" data-action="tray" data-symbol="${esc(el.symbol)}" aria-pressed="${!!inTray}">${inTray ? "✓ In tray" : "+ Tray"}</button>` +
    `<button type="button" class="ptd-nav ptd-nav--next" data-action="next" ${next ? `data-number="${next}"` : "disabled"} aria-label="Next element">›</button>` +
    `<button type="button" class="ptd-close" data-action="close" aria-label="Close element detail">×</button>` +
    `</div>` +
    `</header>`
  );
}

function linksRow(esc, el) {
  const pubchem = `https://pubchem.ncbi.nlm.nih.gov/element/${el.number}`;
  const rsc = `https://periodic-table.rsc.org/element/${el.number}/${encodeURIComponent(String(el.name || "").toLowerCase())}`;
  const wiki = `https://en.wikipedia.org/wiki/${encodeURIComponent(el.name || "")}`;
  const nist = `https://physics.nist.gov/PhysRefData/Handbook/Tables/${encodeURIComponent(String(el.name || "").toLowerCase())}table1.htm`;
  const link = (href, label) => `<a href="${esc(href)}" target="_blank" rel="noopener">${esc(label)}</a>`;
  return `<footer class="ptd-links">${link(pubchem, "PubChem")}${link(rsc, "RSC")}${link(nist, "NIST")}${link(wiki, "Wikipedia")}<button type="button" class="ptd-link-btn" data-action="copy">Copy data as JSON</button></footer>`;
}

function tempRow(tempK, unit) {
  if (tempK == null) return "—";
  return formatTemp(tempK, unit) + (unit !== "K" ? ` <small>(${fmtNum(tempK, 6)} K)</small>` : "");
}

/**
 * Pure render: `deps` = { electrons, chem } modules (passed explicitly so this
 * function can be smoke-tested outside the browser importmap).
 */
export function renderDetailWith(deps, el, opts = {}) {
  const { electrons, chem } = deps;
  const { tempK = 298, unit = "K", categories = {}, neighbours = {}, details = {}, elements = [], inTray = false } = opts;
  const esc = electrons.escapeHtml;

  const fullConfig = electrons.expandConfig((el.electronConfigFull || el.electronConfig || "").replace(/^\*/, ""));
  const parsed = electrons.parseConfig(fullConfig);
  const shells = el.shells && el.shells.length ? el.shells : electrons.shellsFromConfig(parsed);
  const valence = electrons.valenceFromRecord(el);
  const svg = electrons.bohrSVG(shells, { symbol: el.symbol, size: 220 });
  const shellCounts = shells.map((count, i) => `${electrons.SHELL_LETTERS[i] || "?"} ${count}`).join(" · ");
  const conductivity = el.resistivity ? 1 / el.resistivity / 1e6 : null;
  const bioLabel = trendsMod.LENSES.bio.classes[el.bio?.role]?.label;
  const magLabel = trendsMod.LENSES.magnetic.classes[el.magnetic?.ordering]?.label;

  const quick = [
    ["Atomic weight", el.atomicWeightBracketed ? `[${Math.round(el.mass)}]` : fmtNum(el.mass, 7), "u"],
    ["Density", el.density != null ? fmtNum(el.density, 4) : "—", el.densityUnit === "g/L" ? "g/L" : "g/cm³"],
    ["Melts", el.melt != null ? formatTemp(el.melt, unit) : el.sublimes ? "sublimes" : "—", ""],
    ["Boils", el.boil != null ? formatTemp(el.boil, unit) : "—", ""],
    ["χ Pauling", el.electronegativity != null ? fmtNum(el.electronegativity, 3) : "—", ""],
    ["1st IE", el.ionizationEnergies?.[0] != null ? fmtNum(el.ionizationEnergies[0], 5) : "—", "eV"]
  ]
    .map(([k, v, u]) => `<div class="ptd-quick-cell"><span>${k}</span><b>${esc(String(v))}</b>${u ? `<small>${u}</small>` : ""}</div>`)
    .join("");

  const panelBody = {
    overview: () =>
      `<div class="ptd-quick">${quick}</div>` +
      `<p class="ptd-summary">${esc(details.summary || details.description || "")}</p>` +
      (details.description && details.summary ? `<p class="ptd-prose">${esc(details.description)}</p>` : "") +
      `<dl class="ptd-deflist">` +
      row("Appearance", details.appearance ? esc(details.appearance) : null) +
      row("Main uses", details.uses ? esc(details.uses) : null) +
      row("More uses", details.usesDetail ? esc(details.usesDetail) : null) +
      row("Name origin", details.nameOrigin ? esc(details.nameOrigin) : null) +
      row("Biology", bioLabel ? `<b>${esc(bioLabel)}</b>${details.bioNote ? ` — ${esc(details.bioNote)}` : ""}` : null) +
      row("Magnetism", magLabel ? `<b>${esc(magLabel)}</b>${details.magneticNote ? ` — ${esc(details.magneticNote)}` : ""}` : null) +
      row("Radioactivity", el.radioactive ? (el.isotopeSummary?.stable ? "has radioactive isotopes" : "no stable isotopes — every isotope decays") : "has stable isotopes") +
      `</dl>`,
    atom: () =>
      `<div class="ptd-atom-head"><div class="ptd-bohr-wrap">${svg}</div><div>` +
      `<p class="ptd-shell-counts">${esc(shellCounts)}</p>` +
      `<dl class="ptd-deflist">` +
      row("Configuration", esc((el.electronConfig || fullConfig).replace(/^\*/, ""))) +
      row("Full", toSuperscript(esc(fullConfig))) +
      row("Term symbol", el.groundLevel ? `<span class="ptd-term">${termSymbolHTML(esc, el.groundLevel)}</span>` : null) +
      row("Valence electrons", valence != null ? String(valence) : null) +
      `</dl></div></div>` +
      electrons.orbitalDiagramHTML(parsed) +
      section(
        "Electron attraction",
        `<dl class="ptd-deflist">` +
          row("χ Pauling", unitVal(el.electronegativity, "", 3)) +
          row("χ Allen", unitVal(el.enAllen, "", 4), "Average valence-shell ionisation energy (spectroscopic scale).") +
          row("χ Miedema (φ*)", unitVal(el.enMiedema, "V", 3), "Work-function-like parameter used in Miedema's alloy formation-enthalpy model.") +
          row("Electron affinity", unitVal(el.electronAffinity, "eV", 4)) +
          row("Polarisability", unitVal(el.polarizability, "a.u.", 4)) +
          `</dl>`
      ) +
      ionizationStrip(esc, el.ionizationEnergies) +
      radiiBars(el),
    bulk: () =>
      section(
        "Thermal",
        `<dl class="ptd-deflist ptd-deflist--props">` +
          row("Phase at STP", esc(el.phase || "unknown")) +
          row("Melting point", el.melt != null ? tempRow(el.melt, unit) : null) +
          row(el.sublimes ? "Sublimation point" : "Boiling point", el.boil != null ? tempRow(el.boil, unit) : null) +
          row("Critical point", el.critical ? `${tempRow(el.critical.t, unit)}${el.critical.p ? `, ${fmtNum(el.critical.p, 4)} MPa` : ""}` : null) +
          row("Triple point", el.triplePoint ? `${tempRow(el.triplePoint.t, unit)}${el.triplePoint.p != null ? `, ${fmtNum(el.triplePoint.p, 4)} kPa` : ""}` : null) +
          row("Heat of fusion", unitVal(el.heatFusion, "kJ/mol")) +
          row("Heat of vaporisation", unitVal(el.heatVaporization, "kJ/mol")) +
          row("Heat of atomisation", unitVal(el.heatAtomization, "kJ/mol")) +
          row("Specific heat", unitVal(el.specificHeat, "J/(g·K)")) +
          row("Molar heat capacity", unitVal(el.molarHeat, "J/(mol·K)")) +
          row("Thermal conductivity", unitVal(el.thermalConductivity, "W/(m·K)")) +
          row("Thermal expansion", unitVal(el.thermalExpansion, "µm/(m·K)")) +
          `</dl>` +
          ((details.allotropes || []).length
            ? `<p class="ptd-note">Allotropes / phases: ${details.allotropes.map((a) => `${esc(a.name)}${a.melt ? ` (mp ${fmtNum(a.melt, 5)} K${a.transition ? ", transition" : ""})` : ""}`).join(" · ")}</p>`
            : "")
      ) +
      section(
        "Mechanical",
        `<dl class="ptd-deflist ptd-deflist--props">` +
          row("Density", el.density != null ? `${fmtNum(el.density, 5)} ${el.densityUnit === "g/L" ? "g/L" : "g/cm³"}` : null) +
          row("Molar volume", unitVal(el.molarVolume, "cm³/mol")) +
          row("Young's modulus", unitVal(el.youngsModulus, "GPa")) +
          row("Shear modulus", unitVal(el.shearModulus, "GPa")) +
          row("Bulk modulus", unitVal(el.bulkModulus, "GPa")) +
          row("Poisson's ratio", unitVal(el.poissonRatio, "", 3)) +
          row("Pugh ratio G/B", el.shearModulus && el.bulkModulus ? `${fmtNum(el.shearModulus / el.bulkModulus, 3)} ${el.shearModulus / el.bulkModulus < 0.57 ? "(ductile)" : "(brittle)"}` : null, "G/B below ~0.57 predicts ductile behaviour (Pugh 1954).") +
          row("Mohs hardness", unitVal(el.mohsHardness, "", 3)) +
          row("Vickers hardness", unitVal(el.vickersHardness, "MPa")) +
          row("Brinell hardness", unitVal(el.brinellHardness, "MPa")) +
          row("Speed of sound", unitVal(el.speedOfSound, "m/s")) +
          `</dl>`
      ) +
      section(
        "Electrical, magnetic & optical",
        `<dl class="ptd-deflist ptd-deflist--props">` +
          row("Resistivity", sci(el.resistivity, "Ω·m")) +
          row("Conductivity", conductivity != null ? `${fmtNum(conductivity, 4)} MS/m` : null) +
          row("Superconducting Tc", unitVal(el.superconductingTc, "K")) +
          row("Magnetic ordering", magLabel ? esc(magLabel) : null) +
          row("Reflectivity", unitVal(el.reflectivity, "%")) +
          row("Refractive index", unitVal(el.refractiveIndex, "")) +
          `</dl>`
      ) +
      section(
        "Crystal",
        `<dl class="ptd-deflist ptd-deflist--props">` +
          row("Lattice", el.latticeStructure ? esc(trendsMod.LENSES.crystal.classes[el.latticeStructure]?.label || el.latticeStructure) : null) +
          row("Lattice constant a", unitVal(el.latticeConstant, "Å")) +
          row("Mendeleev number", el.mendeleevNumber != null ? String(el.mendeleevNumber) : null) +
          row("Pettifor number", el.pettiforNumber != null ? String(el.pettiforNumber) : null) +
          `</dl>`
      ),
    ions: () => oxidationLine(el) + shannonTable(esc, details.ionicRadii),
    isotopes: () => isotopesSection(esc, el, details),
    compounds: () => compoundsSection(esc, chem, el, elements),
    discovery: () => historySection(esc, el, details),
    earth: () => earthSection(esc, el, details, elements)
  };

  const tabs = [
    { id: "overview", label: "Overview" },
    { id: "atom", label: "Atom" },
    { id: "bulk", label: "Bulk" },
    { id: "ions", label: "Ions" },
    { id: "isotopes", label: "Isotopes" },
    { id: "compounds", label: "Compounds" },
    { id: "discovery", label: "Discovery" },
    { id: "earth", label: "Earth & supply" }
  ];

  const tablistHtml = tabs
    .map(
      (t, i) =>
        `<button type="button" role="tab" id="ptd-tab-${t.id}" aria-controls="ptd-panel-${t.id}" data-tab="${t.id}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}">${esc(t.label)}</button>`
    )
    .join("");
  const panelsHtml = tabs
    .map(
      (t, i) =>
        `<section role="tabpanel" id="ptd-panel-${t.id}" aria-labelledby="ptd-tab-${t.id}" data-panel="${t.id}" ${i === 0 ? "" : "hidden"}>${panelBody[t.id]()}</section>`
    )
    .join("");

  return (
    `<div class="ptable-detail" data-category="${esc(el.category || "unknown")}">` +
    headerPlate(esc, el, { categories, neighbours, tempK, unit, inTray }) +
    `<nav class="ptd-tabs" role="tablist" aria-label="${esc(el.name)} detail sections">${tablistHtml}</nav>` +
    `<div class="ptd-tabpanels">${panelsHtml}</div>` +
    linksRow(esc, el) +
    `</div>`
  );
}

export function renderDetail(el, opts) {
  return renderDetailWith({ electrons: electronsMod, chem: chemMod }, el, opts);
}

// Remembers the last-active tab (module-level) so navigating prev/next keeps
// the visitor on the same tab instead of resetting to Overview each time.
let lastActiveTab = "overview";

export function wireDetail(root, el) {
  const tabs = Array.from(root.querySelectorAll('[role="tab"]'));
  const panels = Array.from(root.querySelectorAll('[role="tabpanel"]'));

  const activate = (name, { focus = false } = {}) => {
    if (!tabs.some((t) => t.dataset.tab === name)) return;
    tabs.forEach((t) => {
      const active = t.dataset.tab === name;
      t.setAttribute("aria-selected", String(active));
      t.tabIndex = active ? 0 : -1;
      if (active) t.scrollIntoView({ block: "nearest", inline: "nearest" });
      if (active && focus) t.focus();
    });
    panels.forEach((p) => {
      p.hidden = p.dataset.panel !== name;
    });
    lastActiveTab = name;
    if (name === "discovery") paintMinimap(root);
  };

  activate(tabs.some((t) => t.dataset.tab === lastActiveTab) ? lastActiveTab : tabs[0]?.dataset.tab ?? "overview");

  const tabList = root.querySelector(".ptd-tabs");
  const onTabClick = (e) => {
    const btn = e.target.closest('[role="tab"]');
    if (!btn) return;
    activate(btn.dataset.tab);
  };
  const onTabKeydown = (e) => {
    const idx = tabs.indexOf(document.activeElement);
    if (idx === -1) return;
    let next = null;
    if (e.key === "ArrowRight") next = tabs[(idx + 1) % tabs.length];
    else if (e.key === "ArrowLeft") next = tabs[(idx - 1 + tabs.length) % tabs.length];
    else if (e.key === "Home") next = tabs[0];
    else if (e.key === "End") next = tabs[tabs.length - 1];
    if (next) {
      e.preventDefault();
      activate(next.dataset.tab, { focus: true });
    }
  };
  tabList?.addEventListener("click", onTabClick);
  tabList?.addEventListener("keydown", onTabKeydown);

  const emit = (name, detail) => root.dispatchEvent(new CustomEvent(name, { bubbles: true, detail }));
  const onRootClick = (e) => {
    const btn = e.target.closest("[data-action]");
    if (!btn || btn.disabled) return;
    const action = btn.dataset.action;
    if (action === "close") {
      emit("periodic-table:close");
    } else if (action === "prev" || action === "next") {
      const number = Number(btn.dataset.number);
      if (Number.isFinite(number)) emit("periodic-table:navigate", { number });
    } else if (action === "tray") {
      emit("periodic-table:tray-toggle", { symbol: btn.dataset.symbol });
      const on = !btn.classList.contains("is-on");
      btn.classList.toggle("is-on", on);
      btn.setAttribute("aria-pressed", String(on));
      btn.textContent = on ? "✓ In tray" : "+ Tray";
    } else if (action === "formula") {
      emit("periodic-bench:open", { tab: "formula", formula: btn.dataset.formula });
    } else if (action === "bench") {
      emit("periodic-bench:open", { tab: btn.dataset.tab, z: btn.dataset.z ? Number(btn.dataset.z) : el.number });
    } else if (action === "copy") {
      import("lib/periodic_table/element_details").then(({ ELEMENT_DETAILS }) => {
        const text = JSON.stringify({ ...el, ...(ELEMENT_DETAILS[el.number] || {}) }, null, 2);
        navigator.clipboard?.writeText(text).then(
          () => { btn.textContent = "Copied ✓"; },
          () => { btn.textContent = "Copy failed"; }
        );
      });
    }
  };
  root.addEventListener("click", onRootClick);

  return () => {
    tabList?.removeEventListener("click", onTabClick);
    tabList?.removeEventListener("keydown", onTabKeydown);
    root.removeEventListener("click", onRootClick);
  };
}

function paintMinimap(root) {
  const land = root.querySelector(".ptd-minimap .ptd-land");
  if (!land || land.getAttribute("d")) return;
  import("lib/periodic_table/world").then(({ LAND_PATH }) => land.setAttribute("d", LAND_PATH));
}
