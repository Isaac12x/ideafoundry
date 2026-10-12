#!/usr/bin/env node
// Builds app/javascript/lib/periodic_table/elements.mjs from three public sources + a
// hand-curated supplement. Node 18+ built-in fetch, zero npm deps.
//
// Usage: node scripts/periodic_table/build_elements.mjs [--offline]
//   --offline   skip network, use whatever is already in tmp/periodic_table_cache/
//
// Sources (see SOURCES export in the generated file for full attribution):
//   1. PubChem periodic table JSON (public domain, NIH/NLM)
//   2. Bowserinator/Periodic-Table-JSON on GitHub (CC-BY-SA 3.0)
//   3. IAEA Live Chart of Nuclides ground-states API (IAEA terms of use)
// Curated (not sourced above): scripts/periodic_table/supplement.json
//
// Caches raw downloads under tmp/periodic_table_cache/ (tmp/ is gitignored) so
// re-runs are offline/reproducible and don't hammer the upstream APIs.

import { writeFileSync, readFileSync, existsSync, mkdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { gunzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const CACHE_DIR = path.join(ROOT, "tmp/periodic_table_cache");
const OUT_FILE = path.join(ROOT, "app/javascript/lib/periodic_table/elements.mjs");
const NUCLIDES_FILE = path.join(ROOT, "app/javascript/lib/periodic_table/nuclides.mjs");
const WORLD_FILE = path.join(ROOT, "app/javascript/lib/periodic_table/world.mjs");
const SUPPLEMENT_FILE = path.join(__dirname, "supplement.json");
const CURATED_FILE = path.join(__dirname, "curated.json");

const OFFLINE = process.argv.includes("--offline");

const URLS = {
  pubchem: "https://pubchem.ncbi.nlm.nih.gov/rest/pug/periodictable/JSON",
  bowserinator:
    "https://raw.githubusercontent.com/Bowserinator/Periodic-Table-JSON/master/PeriodicTableJSON.json",
  iaea: "https://www-nds.iaea.org/relnsd/v1/data?fields=ground_states&nuclides=all",
  // mendeleev (MIT): SQLite database shipped inside the Python package repo.
  mendeleev: "https://raw.githubusercontent.com/lmmentel/mendeleev/master/mendeleev/elements.db",
  // pymatgen-core (MIT): periodic_table.json.gz lives inside the PyPI wheel.
  pymatgenIndex: "https://pypi.org/pypi/pymatgen-core/json",
  naturalEarthLand:
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson",
};

mkdirSync(CACHE_DIR, { recursive: true });

async function cached(name, url, { text = false } = {}) {
  const file = path.join(CACHE_DIR, `${name}.${text ? "csv" : "json"}`);
  if (existsSync(file)) {
    const raw = readFileSync(file, "utf8");
    return text ? raw : JSON.parse(raw);
  }
  if (OFFLINE) throw new Error(`--offline but no cache for ${name} at ${file}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${name} failed: ${res.status}`);
  const raw = text ? await res.text() : JSON.stringify(await res.json());
  writeFileSync(file, raw);
  return text ? raw : JSON.parse(raw);
}

// ---------------------------------------------------------------- fetch/parse

const pubchemRaw = await cached("pubchem", URLS.pubchem);
const bowserinatorRaw = await cached("bowserinator", URLS.bowserinator);
const iaeaCsv = await cached("iaea", URLS.iaea, { text: true });
const supplement = JSON.parse(readFileSync(SUPPLEMENT_FILE, "utf8"));
const curated = JSON.parse(readFileSync(CURATED_FILE, "utf8"));

async function cachedBinary(name, url) {
  const file = path.join(CACHE_DIR, name);
  if (existsSync(file)) return file;
  if (OFFLINE) throw new Error(`--offline but no cache for ${name} at ${file}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${name} failed: ${res.status}`);
  writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  return file;
}

// Minimal ZIP reader for one stored/deflated member (PyPI wheels are zips).
function extractFromZip(buffer, suffix) {
  const { inflateRawSync } = process.getBuiltinModule("node:zlib");
  let eocd = buffer.length - 22;
  while (eocd >= 0 && buffer.readUInt32LE(eocd) !== 0x06054b50) eocd--;
  const entries = buffer.readUInt16LE(eocd + 10);
  let ptr = buffer.readUInt32LE(eocd + 16);
  for (let i = 0; i < entries; i++) {
    const method = buffer.readUInt16LE(ptr + 10);
    const compSize = buffer.readUInt32LE(ptr + 20);
    const nameLen = buffer.readUInt16LE(ptr + 28);
    const extraLen = buffer.readUInt16LE(ptr + 30);
    const commentLen = buffer.readUInt16LE(ptr + 32);
    const localOffset = buffer.readUInt32LE(ptr + 42);
    const name = buffer.toString("utf8", ptr + 46, ptr + 46 + nameLen);
    if (name.endsWith(suffix)) {
      const lNameLen = buffer.readUInt16LE(localOffset + 26);
      const lExtraLen = buffer.readUInt16LE(localOffset + 28);
      const start = localOffset + 30 + lNameLen + lExtraLen;
      const data = buffer.subarray(start, start + compSize);
      return method === 0 ? data : inflateRawSync(data);
    }
    ptr += 46 + nameLen + extraLen + commentLen;
  }
  throw new Error(`${suffix} not found in zip`);
}

async function loadPymatgen() {
  const file = path.join(CACHE_DIR, "pymatgen.json");
  if (existsSync(file)) return JSON.parse(readFileSync(file, "utf8"));
  if (OFFLINE) throw new Error(`--offline but no cache for pymatgen at ${file}`);
  const index = await (await fetch(URLS.pymatgenIndex)).json();
  const wheel = index.urls.find((u) => u.packagetype === "bdist_wheel");
  const zip = Buffer.from(await (await fetch(wheel.url)).arrayBuffer());
  const json = gunzipSync(extractFromZip(zip, "pymatgen/core/periodic_table.json.gz")).toString("utf8");
  writeFileSync(file, json);
  return JSON.parse(json);
}

const mendeleevDb = new DatabaseSync(await cachedBinary("mendeleev.db", URLS.mendeleev), { readOnly: true });
const pymatgen = await loadPymatgen();
const landGeo = JSON.parse(readFileSync(await cachedBinary("ne_110m_land.json", URLS.naturalEarthLand), "utf8"));

// -- PubChem: row-per-element table, columns array gives field order.
const pcCols = pubchemRaw.Table.Columns.Column;
const pcIdx = Object.fromEntries(pcCols.map((c, i) => [c, i]));
const pubchemBySymbol = new Map();
for (const row of pubchemRaw.Table.Row) {
  const cell = row.Cell;
  const get = (col) => {
    const v = cell[pcIdx[col]];
    return v === "" || v === undefined ? null : v;
  };
  pubchemBySymbol.set(get("Symbol"), {
    mass: get("AtomicMass") ? parseFloat(get("AtomicMass")) : null,
    electronegativity: get("Electronegativity") ? parseFloat(get("Electronegativity")) : null,
    atomicRadius: get("AtomicRadius") ? parseFloat(get("AtomicRadius")) : null,
    ionizationEnergyFirst: get("IonizationEnergy") ? parseFloat(get("IonizationEnergy")) : null,
    electronAffinity: get("ElectronAffinity") ? parseFloat(get("ElectronAffinity")) : null,
    oxidationStates: get("OxidationStates")
      ? get("OxidationStates")
          .split(",")
          .map((s) => parseInt(s.trim(), 10))
          .filter((n) => !Number.isNaN(n))
      : [],
    standardState: get("StandardState"),
    melt: get("MeltingPoint") ? parseFloat(get("MeltingPoint")) : null,
    boil: get("BoilingPoint") ? parseFloat(get("BoilingPoint")) : null,
    density: get("Density") ? parseFloat(get("Density")) : null,
    groupBlock: get("GroupBlock"),
    yearDiscovered: get("YearDiscovered"),
    cpkHex: get("CPKHexColor"),
  });
}

// -- Bowserinator: elements[] array, richest single source.
const bowserinatorElements = bowserinatorRaw.elements.filter((e) => e.number <= 118);

// eV per kJ/mol (Bowserinator's ionization_energies / electron_affinity are kJ/mol)
const EV_PER_KJMOL = 1 / 96.485;

// -- IAEA Live Chart ground states CSV -> every known nuclide + isotopes by Z.
const HBAR_EV_S = 6.582119569e-16;
const WIDTH_UNITS = { eV: 1, keV: 1e3, MeV: 1e6 };
const sig = (v, d = 4) => (v == null || !Number.isFinite(v) ? null : Number(v.toPrecision(d)));

function humanHalfLife(sec) {
  if (sec == null) return null;
  const units = [
    [365.2422 * 86400 * 1e9, "Gy"], [365.2422 * 86400 * 1e6, "My"], [365.2422 * 86400 * 1e3, "ky"],
    [365.2422 * 86400, "y"], [86400, "d"], [3600, "h"], [60, "min"], [1, "s"],
    [1e-3, "ms"], [1e-6, "µs"], [1e-9, "ns"], [1e-12, "ps"], [1e-15, "fs"], [1e-18, "as"], [1e-21, "zs"], [1e-24, "ys"]
  ];
  for (const [f, u] of units) if (sec >= f) return `${Number((sec / f).toPrecision(3))} ${u}`;
  return `${Number((sec / 1e-24).toPrecision(3))} ys`;
}

function parseIaea(csv) {
  const lines = csv.trim().split("\n");
  const header = lines[0].split(",");
  const col = (k) => header.indexOf(k);
  const I = {
    z: col("z"), n: col("n"), abund: col("abundance"), hl: col("half_life"), op: col("operator_hl"), unit: col("unit_hl"),
    hlSec: col("half_life_sec"), d1: col("decay_1"), d1p: col("decay_1_%"), d2: col("decay_2"), d2p: col("decay_2_%"),
    jp: col("jp"), mass: col("atomic_mass"), binding: col("binding"), mu: col("magnetic_dipole"), disc: col("discovery")
  };

  const nuclides = [];
  const byZ = new Map();
  for (let i = 1; i < lines.length; i++) {
    const c = lines[i].split(",");
    const z = parseInt(c[I.z], 10);
    const n = parseInt(c[I.n], 10);
    if (!Number.isFinite(z) || !Number.isFinite(n) || z === 0) continue;
    const stable = c[I.hl] === "STABLE";
    const abundance = c[I.abund] ? parseFloat(c[I.abund]) : 0;
    let halfLifeSec = c[I.hlSec] ? parseFloat(c[I.hlSec]) : null;
    let halfLife = null;
    let resonance = false;
    if (!stable && c[I.hl]) {
      const unit = c[I.unit] || "";
      if (WIDTH_UNITS[unit]) {
        // Unbound resonances are quoted as a level width Γ; t½ = ħ·ln2 / Γ.
        resonance = true;
        const gammaEv = parseFloat(c[I.hl]) * WIDTH_UNITS[unit];
        halfLifeSec = gammaEv > 0 ? (HBAR_EV_S * Math.LN2) / gammaEv : null;
        halfLife = `unbound (Γ = ${c[I.hl]} ${unit})`;
      } else {
        const op = c[I.op] || "";
        halfLife = `${op}${c[I.hl]} ${unit}`.trim();
      }
    }
    const decay = c[I.d1] || null;
    const decay2 = c[I.d2] || null;
    const exactMass = c[I.mass] ? parseFloat(c[I.mass]) / 1e6 : null;
    const binding = c[I.binding] ? parseFloat(c[I.binding]) : null; // keV per nucleon

    // Compact chart row: [Z, N, t½ s (-1 stable, null unknown), mode, abundance %, Jπ, B/A keV, discovery year]
    nuclides.push([z, n, stable ? -1 : sig(halfLifeSec, 3), decay, abundance || 0, c[I.jp] || null, sig(binding, 5), c[I.disc] ? parseInt(c[I.disc], 10) || null : null]);

    if (!byZ.has(z)) byZ.set(z, []);
    byZ.get(z).push({
      mass: z + n, abundance, halfLife, halfLifeSec, stable, resonance, decay,
      decayPct: c[I.d1p] ? parseFloat(c[I.d1p]) : null, decay2, exactMass, spin: c[I.jp] || null,
      magneticMoment: c[I.mu] ? parseFloat(c[I.mu]) : null
    });
  }

  // Per element: every naturally occurring isotope + the longest-lived others (cap 10).
  const out = new Map();
  for (const [z, list] of byZ) {
    const natural = list.filter((x) => x.stable || x.abundance > 0);
    const radio = list
      .filter((x) => !x.stable && x.abundance === 0 && !x.resonance)
      .sort((a, b) => (b.halfLifeSec ?? -1) - (a.halfLifeSec ?? -1))
      .slice(0, Math.max(0, 10 - natural.length));
    out.set(z, {
      known: list.length,
      list: [...natural, ...radio]
        .sort((a, b) => a.mass - b.mass)
        .map((x) => ({
          mass: x.mass,
          exactMass: x.exactMass != null ? Number(x.exactMass.toFixed(7)) : null,
          abundance: x.abundance > 0 ? sig(x.abundance, 5) : 0,
          halfLife: x.stable ? null : x.halfLife ?? null,
          halfLifeSec: x.stable ? null : sig(x.halfLifeSec, 4),
          ...(x.halfLifeSec != null && !x.stable ? { halfLifeHuman: humanHalfLife(x.halfLifeSec) } : {}),
          stable: x.stable,
          decay: x.decay,
          ...(x.decayPct != null ? { decayPct: x.decayPct } : {}),
          ...(x.decay2 ? { decay2: x.decay2 } : {}),
          spin: x.spin,
          ...(x.magneticMoment != null ? { magneticMoment: x.magneticMoment } : {})
        }))
    });
  }
  return { byZ: out, nuclides };
}
const { byZ: isotopesByZ, nuclides: NUCLIDES } = parseIaea(iaeaCsv);

// ------------------------------------------------------------------ mappings

// Bowserinator category string -> spec CATEGORIES key
function mapCategory(bowserinatorCategory, number) {
  const c = (bowserinatorCategory || "").toLowerCase();
  if (c.includes("unknown")) return "unknown";
  if (c.includes("noble gas")) return "noble-gas";
  if (c.includes("alkaline earth")) return "alkaline-earth-metal";
  if (c.includes("alkali metal")) return "alkali-metal";
  if (c.includes("lanthanide")) return "lanthanide";
  if (c.includes("actinide")) return "actinide";
  if (c.includes("metalloid")) return "metalloid";
  if (c.includes("post-transition")) return "post-transition-metal";
  if (c.includes("transition metal")) return "transition-metal";
  if (c.includes("diatomic nonmetal") || c.includes("polyatomic nonmetal") || c.includes("nonmetal"))
    return "reactive-nonmetal";
  return "unknown";
}

const ANCIENT = new Set(["C", "S", "Fe", "Cu", "Ag", "Sn", "Au", "Hg", "Pb", "Sb", "Zn"]);

function valenceForMainGroup(group) {
  if (group === null || group === undefined) return null;
  if (group === 1) return 1;
  if (group === 2) return 2;
  if (group >= 13 && group <= 18) {
    const v = group - 10;
    return v === 8 && group === 18 ? 8 : v; // He handled separately (2)
  }
  return null;
}

// ponytail: periodictableguide.com was unreachable from this environment, so
// transition/f-block valence falls back to "outer-shell s electron count"
// (documented fallback per spec) parsed from the semantic electron config.
function valenceFallbackFromConfig(semanticConfig) {
  if (!semanticConfig) return null;
  // subshell terms aren't reliably space-separated (e.g. "[Xe] 5d16s2"), so
  // scan the whole string for every N-s-electrons term and take the highest N.
  let highestN = 0,
    sElectrons = null;
  for (const m of semanticConfig.matchAll(/(\d+)s(\d+)/g)) {
    const n = parseInt(m[1], 10);
    if (n >= highestN) {
      highestN = n;
      sElectrons = parseInt(m[2], 10);
    }
  }
  return sElectrons;
}

// -------------------------------------------------------------- assemble

const elements = bowserinatorElements
  .map((b) => {
    const pc = pubchemBySymbol.get(b.symbol) || {};
    const category = mapCategory(b.category, b.number);
    const ancient = ANCIENT.has(b.symbol);
    const sup = supplement[b.symbol] || {};

    // spec: group is null for the whole lanthanide/actinide row (La-Lu, Ac-Lr).
    // Bowserinator assigns group=3 to all of them (incl. Lu/Lr, which it places
    // in the d-block) — override by category, which is the spec's own rule.
    const group = category === "lanthanide" || category === "actinide" ? null : (b.group ?? null);
    const isMainGroup = b.block === "s" || b.block === "p";
    const valence = isMainGroup
      ? b.number === 2
        ? 2
        : valenceForMainGroup(b.group)
      : valenceFallbackFromConfig(b.electron_configuration_semantic);

    const isotopeInfo = isotopesByZ.get(b.number) || { list: [], known: 0 };
    const isotopes = isotopeInfo.list;

    const massApprox = !Number.isFinite(pc.mass) && !Number.isFinite(b.atomic_mass);
    const mass = Number.isFinite(pc.mass) ? pc.mass : Number.isFinite(b.atomic_mass) ? b.atomic_mass : null;

    const yearDiscovered =
      ancient || pc.yearDiscovered === "Ancient" || pc.yearDiscovered === null
        ? null
        : /^\d+$/.test(pc.yearDiscovered || "")
          ? parseInt(pc.yearDiscovered, 10)
          : null;

    const record = {
      number: b.number,
      symbol: b.symbol,
      name: b.name,
      mass,
      ...(massApprox ? { massApprox: true } : {}),
      category,
      group,
      period: b.period,
      block: b.block,
      xpos: b.xpos,
      ypos: b.ypos,
      wxpos: b.wxpos,
      wypos: b.wypos,
      phase: (b.phase || pc.standardState || "unknown").toLowerCase(),
      melt: Number.isFinite(b.melt) ? b.melt : pc.melt,
      boil: Number.isFinite(b.boil) ? b.boil : pc.boil,
      density: Number.isFinite(b.density) ? b.density : pc.density,
      densityUnit: category === "noble-gas" || b.phase === "Gas" ? "g/L" : "g/cm3",
      electronConfig: b.electron_configuration_semantic || null,
      electronConfigFull: b.electron_configuration || null,
      shells: b.shells || [],
      valence: Number.isFinite(valence) ? valence : null,
      electronegativity: Number.isFinite(b.electronegativity_pauling)
        ? b.electronegativity_pauling
        : pc.electronegativity,
      atomicRadius: pc.atomicRadius,
      ionizationEnergies:
        Array.isArray(b.ionization_energies) && b.ionization_energies.length
          ? b.ionization_energies.map((v) => Math.round(v * EV_PER_KJMOL * 1000) / 1000)
          : pc.ionizationEnergyFirst
            ? [pc.ionizationEnergyFirst]
            : [],
      electronAffinity: Number.isFinite(b.electron_affinity)
        ? Math.round(b.electron_affinity * EV_PER_KJMOL * 1000) / 1000
        : pc.electronAffinity,
      oxidationStates: pc.oxidationStates || [],
      yearDiscovered,
      ...(ancient ? { ancient: true } : {}),
      discoveredBy: b.discovered_by && !/^\d/.test(b.discovered_by) ? b.discovered_by : null,
      namedBy: b.named_by || null,
      ...(sup.discoveryPlace ? { discoveryPlace: sup.discoveryPlace } : {}),
      nameOrigin: sup.nameOrigin || null,
      appearance: b.appearance || null,
      summary: b.summary || null,
      uses: sup.uses || null,
      abundanceCrust: sup.abundanceCrust ?? null,
      ...(sup.abundanceUniverse ? { abundanceUniverse: sup.abundanceUniverse } : {}),
      cpkHex: b["cpk-hex"] || pc.cpkHex || null,
      molarHeat: Number.isFinite(b.molar_heat) ? b.molar_heat : null,
      ...(sup.thermalConductivity ? { thermalConductivity: sup.thermalConductivity } : {}),
      isotopes,
      isotopesKnown: isotopeInfo.known,
      ...(sup.crystalStructure ? { crystalStructure: sup.crystalStructure } : {}),
      ...(sup.nuclearNote ? { nuclearNote: sup.nuclearNote } : {}),
    };
    return record;
  })
  .sort((a, b) => a.number - b.number);

// ------------------------------------------------------------- enrichment
// mendeleev (atomic weights, radii, thermochemistry, Shannon radii, oxidation
// states, geochemistry, supply risk) + pymatgen (mechanical/electrical, full
// ionisation series, term symbols) + curated.json (corrected discovery history
// with coordinates, biological role, magnetic ordering).

const num = (v) => (v == null || v === "" || !Number.isFinite(Number(v)) ? null : Number(v));
const round = (v, d = 4) => (v == null ? null : Number(Number(v).toPrecision(d)));
const mdRows = new Map(mendeleevDb.prepare("SELECT * FROM elements").all().map((r) => [r.atomic_number, r]));
const groupBy = (rows) => rows.reduce((m, r) => m.set(r.atomic_number, [...(m.get(r.atomic_number) || []), r]), new Map());
const mdOx = groupBy(mendeleevDb.prepare("SELECT atomic_number, oxidation_state, category FROM oxidationstates").all());
const mdIonic = groupBy(mendeleevDb.prepare("SELECT * FROM ionicradii ORDER BY charge, coordination").all());
const mdPhase = groupBy(mendeleevDb.prepare("SELECT * FROM phasetransitions").all());
const ROMAN_CN = { I: 1, II: 2, III: 3, IV: 4, IVSQ: 4, V: 5, VI: 6, VII: 7, VIII: 8, IX: 9, X: 10, XI: 11, XII: 12, XIV: 14, IIIPY: 3, IVPY: 4, VIPY: 6 };
const parseRank = (str) => (str ? str.split(/\s*\d\)\s*/).map((x) => x.trim()).filter(Boolean) : []);
const STANDARD_WEIGHT_RADIOACTIVE = new Set([83, 90, 91, 92]);

function enrich(rec) {
  const md = mdRows.get(rec.number) || {};
  const pm = pymatgen[rec.symbol] || {};
  const cur = curated[rec.symbol] || {};
  const z = rec.number;

  // Atomic weight: IUPAC standard (mendeleev) — fixes conventional "7" for Li etc.
  const atomicWeight = num(md.atomic_weight) ?? rec.mass;
  const bracketed = !!md.is_radioactive && !STANDARD_WEIGHT_RADIOACTIVE.has(z);

  const ox = mdOx.get(z) || [];
  const oxidationMain = ox.filter((o) => o.category === "main").map((o) => o.oxidation_state).sort((a, b) => b - a);
  const oxidationAll = [...new Set(ox.map((o) => o.oxidation_state))].sort((a, b) => b - a);

  const phases = mdPhase.get(z) || [];
  const primary = phases.find((p) => !p.is_transition) || phases[0] || {};
  const critical = phases.find((p) => p.critical_temperature != null);
  const triple = phases.find((p) => p.triple_point_temperature != null);
  const allotropes = phases.filter((p) => p.allotrope).map((p) => ({
    name: p.allotrope, melt: round(p.melting_point, 5), boil: round(p.boiling_point, 5), sublimes: !!p.is_sublimation_point, transition: !!p.is_transition
  }));

  const ionicRadii = (mdIonic.get(z) || []).map((r) => [
    r.charge, r.coordination, r.spin || null, round(r.crystal_radius, 4), round(r.ionic_radius, 4), r.most_reliable ? 1 : 0, ROMAN_CN[r.coordination] ?? null
  ]);

  // pymatgen's series is complete for most elements, but some superheavy
  // entries start at a higher ion (Mt, Ds list 1st IE > 50 eV). No neutral atom
  // exceeds helium's 24.6 eV, and the series must increase — otherwise fall back.
  const pmIe = Array.isArray(pm["Ionization energies"]) ? pm["Ionization energies"].map((v) => num(v)) : [];
  const pmIeValid = pmIe.length > 0 && pmIe.every((v) => v != null) && pmIe[0] <= 24.6 &&
    pmIe.every((v, i) => i === 0 || v > pmIe[i - 1]);
  const ie = pmIeValid ? pmIe.map((v) => round(v, 6)) : rec.ionizationEnergies;

  const [dYear, dWho, dPlace, dLat, dLon, dMethod, dNote] = cur.d || [];
  const thermalExpansion = num(pm["Coefficient of linear thermal expansion"]);

  const supply = md.relative_supply_risk != null || md.price_per_kg != null ? {
    risk: num(md.relative_supply_risk),
    producers: parseRank(md.top_3_producers),
    reserves: parseRank(md.top_3_reserve_holders),
    recycling: md.recycling_rate || null,
    substitutability: md.substitutability || null,
    pricePerKg: num(md.price_per_kg),
    productionConcentration: num(md.production_concentration),
    reserveDistribution: num(md.reserve_distribution),
    stabilityProducer: num(md.political_stability_of_top_producer),
    stabilityReserve: num(md.political_stability_of_top_reserve_holder)
  } : null;

  return {
    ...rec,
    mass: atomicWeight,
    atomicWeight,
    atomicWeightUncertainty: num(md.atomic_weight_uncertainty),
    ...(bracketed ? { atomicWeightBracketed: true } : {}),
    massApprox: undefined,
    cas: md.cas || null,
    radioactive: !!md.is_radioactive,
    monoisotopic: !!md.is_monoisotopic,
    mendeleevNumber: num(md.mendeleev_number),
    pettiforNumber: num(md.pettifor_number),
    glaweNumber: num(md.glawe_number),
    // radii (pm)
    covalentRadius: num(md.covalent_radius_cordero),
    covalentRadiusPyykko: [num(md.covalent_radius_pyykko), num(md.covalent_radius_pyykko_double), num(md.covalent_radius_pyykko_triple)],
    vdwRadius: num(md.vdw_radius_alvarez) ?? num(md.vdw_radius),
    metallicRadius: num(md.metallic_radius_c12) ?? num(md.metallic_radius),
    atomicRadiusCalc: num(md.atomic_radius_rahm),
    ionicRadii,
    // electronic
    electronegativity: rec.electronegativity ?? num(md.en_pauling),
    enAllen: num(md.en_allen),
    enMiedema: num(md.en_miedema),
    electronAffinity: num(pm["Electron affinity"]) != null ? round(pm["Electron affinity"], 5) : rec.electronAffinity,
    ionizationEnergies: ie,
    polarizability: num(md.dipole_polarizability),
    groundLevel: typeof pm["Ground level"] === "string" ? pm["Ground level"] : null,
    oxidationMain: oxidationMain.length ? oxidationMain : rec.oxidationStates,
    oxidationStates: oxidationAll.length ? oxidationAll : rec.oxidationStates,
    oxidationIcsd: Array.isArray(pm["ICSD oxidation states"]) ? pm["ICSD oxidation states"] : [],
    // thermal
    melt: rec.melt ?? round(primary.melting_point, 6),
    boil: rec.boil ?? round(primary.boiling_point, 6),
    sublimes: !!primary.is_sublimation_point,
    critical: critical ? { t: round(critical.critical_temperature, 5), p: round(critical.critical_pressure, 4) } : null,
    triplePoint: triple ? { t: round(triple.triple_point_temperature, 6), p: round(triple.triple_point_pressure, 4) } : null,
    allotropes: allotropes.length > 1 || allotropes.some((a) => a.transition) ? allotropes : [],
    heatFusion: num(md.fusion_heat),
    heatVaporization: num(md.evaporation_heat),
    heatAtomization: num(md.heat_of_formation),
    specificHeat: num(md.specific_heat_capacity),
    molarHeat: rec.molarHeat ?? num(md.molar_heat_capacity),
    thermalConductivity: num(md.thermal_conductivity) ?? rec.thermalConductivity ?? null,
    thermalExpansion: thermalExpansion != null ? round(thermalExpansion * 1e6, 4) : null, // µm/(m·K)
    // mechanical (GPa / MPa / m/s)
    youngsModulus: num(pm["Youngs modulus"]),
    shearModulus: num(pm["Rigidity modulus"]),
    bulkModulus: num(pm["Bulk modulus"]),
    poissonRatio: num(pm["Poissons ratio"]),
    mohsHardness: num(pm["Mineral hardness"]),
    vickersHardness: num(pm["Vickers hardness"]),
    brinellHardness: num(pm["Brinell hardness"]),
    speedOfSound: num(pm["Velocity of sound"]),
    molarVolume: num(pm["Molar volume"]),
    // electrical / optical / magnetic
    resistivity: num(pm["Electrical resistivity"]),
    reflectivity: num(pm["Reflectivity"]),
    refractiveIndex: num(pm["Refractive index"]),
    superconductingTc: num(pm["Superconduction temperature"]),
    magnetic: cur.mag ? { ordering: cur.mag[0], note: cur.mag[1] || null } : null,
    // structure
    latticeStructure: md.lattice_structure || null,
    latticeConstant: num(md.lattice_constant),
    // earth & economy
    abundanceCrust: rec.abundanceCrust ?? num(md.abundance_crust),
    abundanceSea: num(md.abundance_sea),
    goldschmidt: md.goldschmidt_class ? md.goldschmidt_class.replace("litophile", "lithophile") : null,
    geochemicalClass: md.geochemical_class || null,
    occurrence: md.sources || null,
    usesDetail: md.uses || null,
    description: md.description || null,
    supply,
    // discovery (curated, corrected)
    // Ancient elements keep yearDiscovered null; their earliest-use date is separate.
    yearDiscovered: rec.ancient ? null : dYear ?? rec.yearDiscovered,
    ...(rec.ancient && dYear != null ? { earliestUse: dYear } : {}),
    discoveredBy: dWho ?? rec.discoveredBy,
    discoveryPlace: dPlace ?? rec.discoveryPlace ?? null,
    discoveryLat: dLat ?? null,
    discoveryLon: dLon ?? null,
    discoveryMethod: dMethod ?? null,
    discoveryNote: dNote ?? null,
    bio: cur.bio ? { role: cur.bio[0], note: cur.bio[1] } : null
  };
}

// Core records feed the grid, trends and workbench on first paint; bulky
// per-element material (long text, isotope tables, Shannon radii, allotropes,
// supply chain) goes to element_details.mjs, loaded when a panel needs it.
const DETAIL_KEYS = ["summary", "description", "occurrence", "usesDetail", "uses", "nameOrigin", "appearance", "discoveryNote", "isotopes", "ionicRadii", "allotropes", "supply", "nuclearNote", "namedBy"];
const details = {};
const enriched = elements.map((rec) => {
  const out = enrich(rec);
  for (const k of Object.keys(out)) if (out[k] === undefined) delete out[k];
  const detail = {};
  for (const k of DETAIL_KEYS) {
    if (k in out) { detail[k] = out[k]; delete out[k]; }
  }
  if (out.bio?.note) { detail.bioNote = out.bio.note; out.bio = { role: out.bio.role }; }
  if (out.magnetic?.note) { detail.magneticNote = out.magnetic.note; out.magnetic = { ordering: out.magnetic.ordering }; }
  const iso = detail.isotopes || [];
  out.isotopeSummary = { listed: iso.length, stable: iso.filter((i) => i.stable).length, natural: iso.filter((i) => i.stable || i.abundance > 0).length };
  out.supplyRisk = detail.supply?.risk ?? null;
  out.pricePerKg = detail.supply?.pricePerKg ?? null;
  details[out.number] = detail;
  return out;
});

// Trim float noise (115.99999999999999 → 116) while keeping isotope-mass precision.
const tidy = (_k, v) => (typeof v === "number" && !Number.isInteger(v) ? Number(v.toPrecision(10)) : v);
const DETAILS_FILE = path.join(ROOT, "app/javascript/lib/periodic_table/element_details.mjs");

// ---------------------------------------------------------- world outline
// Equirectangular projection in a 360×150 box (lon −180…180, lat 90…−60);
// Antarctica is clipped since no element was discovered there.
function landPath(geo) {
  const ring = (coords) => {
    const pts = coords.map(([lon, lat]) => [Math.round((lon + 180) * 10) / 10, Math.round((90 - Math.max(lat, -60)) * 10) / 10]);
    const dedup = pts.filter((p, i) => i === 0 || p[0] !== pts[i - 1][0] || p[1] !== pts[i - 1][1]);
    return dedup.length > 2 ? "M" + dedup.map((p) => p.join(" ")).join("L") + "Z" : "";
  };
  return geo.features
    .flatMap((f) => (f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates))
    .map((poly) => poly.map(ring).join(""))
    .join("");
}

// ------------------------------------------------------------------ output

const CATEGORIES = {
  "alkali-metal": { label: "Alkali metal" },
  "alkaline-earth-metal": { label: "Alkaline earth metal" },
  "transition-metal": { label: "Transition metal" },
  "post-transition-metal": { label: "Post-transition metal" },
  metalloid: { label: "Metalloid" },
  "reactive-nonmetal": { label: "Reactive nonmetal" },
  "noble-gas": { label: "Noble gas" },
  lanthanide: { label: "Lanthanide" },
  actinide: { label: "Actinide" },
  unknown: { label: "Unknown" },
};

const SOURCES = [
  {
    name: "PubChem Periodic Table",
    url: "https://pubchem.ncbi.nlm.nih.gov/periodic-table/",
    license: "Public domain (NIH/NLM)",
  },
  {
    name: "Bowserinator/Periodic-Table-JSON",
    url: "https://github.com/Bowserinator/Periodic-Table-JSON",
    license: "CC-BY-SA 3.0",
  },
  {
    name: "IAEA Live Chart of Nuclides",
    url: "https://www-nds.iaea.org/relnsd/vcharthtml/VChartHTML.html",
    license: "IAEA terms of use (data free for non-commercial/educational use with attribution)",
  },
  {
    name: "mendeleev (L. M. Mentel) — atomic weights, radii, Shannon ionic radii, thermochemistry, oxidation states, geochemistry, supply-risk data",
    url: "https://github.com/lmmentel/mendeleev",
    license: "MIT",
  },
  {
    name: "pymatgen (Materials Project) — mechanical, electrical, ionisation and term-symbol data",
    url: "https://github.com/materialsproject/pymatgen",
    license: "MIT",
  },
  {
    name: "Natural Earth 1:110m land",
    url: "https://www.naturalearthdata.com/",
    license: "Public domain",
  },
  {
    name: "Curated discovery history (corrected dates, discoverers, coordinates, methods), biological role and magnetic ordering",
    url: "scripts/periodic_table/curated.json",
    license: "Original, this repository",
  },
  {
    name: "Hand-curated supplement (name origins, uses, discovery places, crustal abundance, crystal structure, thermal conductivity, nuclear-fuel-cycle notes)",
    url: "scripts/periodic_table/supplement.json",
    license: "Original, this repository",
  },
];

const header = `// AUTO-GENERATED by scripts/periodic_table/build_elements.mjs — do not hand-edit.
// Re-run: node scripts/periodic_table/build_elements.mjs
//
// Sources & licenses:
//   - PubChem Periodic Table (public domain, NIH/NLM)
//   - Bowserinator/Periodic-Table-JSON (CC-BY-SA 3.0) https://github.com/Bowserinator/Periodic-Table-JSON
//   - IAEA Live Chart of Nuclides ground-states API (IAEA terms of use)
//   - mendeleev (MIT) https://github.com/lmmentel/mendeleev
//   - pymatgen (MIT) https://github.com/materialsproject/pymatgen
//   - Hand-curated: scripts/periodic_table/supplement.json + curated.json (original)
//
// No imports here (elements.mjs must stay dependency-free per the shared contract).
`;

const body =
  header +
  `\nexport const CATEGORIES = ${JSON.stringify(CATEGORIES, null, 2)};\n` +
  `\nexport const SOURCES = ${JSON.stringify(SOURCES, null, 2)};\n` +
  `\nexport const ELEMENTS = [\n${enriched.map((e) => "  " + JSON.stringify(e, tidy)).join(",\n")}\n];\n`;

mkdirSync(path.dirname(OUT_FILE), { recursive: true });
writeFileSync(OUT_FILE, body);
console.log(`wrote ${OUT_FILE} (${enriched.length} elements, ${(body.length / 1024).toFixed(1)} KB)`);

const detailsBody = `// AUTO-GENERATED by scripts/periodic_table/build_elements.mjs — do not hand-edit.
// Long-form per-element material keyed by atomic number (see elements.mjs for sources).
// ionicRadii rows: [charge, coordination, spin, crystal radius pm, ionic radius pm, most reliable 0/1, CN]
export const ELEMENT_DETAILS = {
${Object.entries(details).map(([n, d]) => `  ${n}: ${JSON.stringify(d, tidy)}`).join(",\n")}
};
`;
writeFileSync(DETAILS_FILE, detailsBody);
console.log(`wrote ${DETAILS_FILE} (${(detailsBody.length / 1024).toFixed(1)} KB)`);

const nuclideBody = `// AUTO-GENERATED by scripts/periodic_table/build_elements.mjs — do not hand-edit.
// Source: IAEA Live Chart of Nuclides ground states (IAEA terms of use).
// Row: [Z, N, half-life seconds (-1 = stable, null = unknown), primary decay mode,
//       natural abundance %, spin-parity Jπ, binding energy per nucleon keV, discovery year]
export const NUCLIDES = [
${NUCLIDES.map((r) => JSON.stringify(r)).join(",\n")}
];
`;
writeFileSync(NUCLIDES_FILE, nuclideBody);
console.log(`wrote ${NUCLIDES_FILE} (${NUCLIDES.length} nuclides, ${(nuclideBody.length / 1024).toFixed(1)} KB)`);

const worldBody = `// AUTO-GENERATED by scripts/periodic_table/build_elements.mjs — do not hand-edit.
// Natural Earth 1:110m land (public domain), equirectangular, viewBox "0 0 360 150"
// (x = lon + 180, y = 90 − lat, clipped at 60° S).
export const LAND_PATH = ${JSON.stringify(landPath(landGeo))};
`;
writeFileSync(WORLD_FILE, worldBody);
console.log(`wrote ${WORLD_FILE} (${(worldBody.length / 1024).toFixed(1)} KB)`);
