// Pure helpers for the periodic table: property metadata and scales,
// classification lenses, state-at-temperature, discovery gating, temperature
// formatting. No imports (node-testable, and importable bare as
// "lib/periodic_table/trends" from the browser).

// Each property: label, unit, group, optional log scale, digits, and `trend` —
// one or two sentences on what the pattern across the table means.
export const PROPERTIES = {
  mass: { label: "Atomic weight", unit: "u", group: "Atomic", trend: "Rises with atomic number, but not strictly: Ar > K, Co > Ni, Te > I and Th > Pa are inversions because isotope mixtures differ — the reason Mendeleev ordered by properties, and Moseley later by charge." },
  electronegativity: { label: "Electronegativity (Pauling)", unit: "", group: "Atomic", trend: "Increases left → right and bottom → top, peaking at fluorine (3.98). The difference between two atoms predicts bond polarity: >1.7 is largely ionic." },
  enAllen: { label: "Electronegativity (Allen)", unit: "", group: "Atomic", trend: "Allen's scale is the average valence-electron ionisation energy — a spectroscopic, not thermochemical, measure; it also assigns values to the noble gases." },
  atomicRadius: { label: "Atomic radius (empirical)", unit: "pm", group: "Atomic", trend: "Shrinks across a period as nuclear charge grows with no new shell; grows down a group as shells are added. Caesium/francium are the largest." },
  covalentRadius: { label: "Covalent radius", unit: "pm", group: "Atomic", trend: "Half the single-bond length between like atoms (Cordero 2008). Sums of covalent radii estimate bond lengths to ~±5 pm." },
  vdwRadius: { label: "Van der Waals radius", unit: "pm", group: "Atomic", trend: "Contact distance between non-bonded atoms — sets molecular packing, steric clashes and gas-kinetic size." },
  metallicRadius: { label: "Metallic radius (CN 12)", unit: "pm", group: "Atomic", trend: "Half the nearest-neighbour distance in a 12-coordinate metal. Used in Hume-Rothery size rules: <15% difference allows wide solid solubility." },
  ionization1: { label: "1st ionisation energy", unit: "eV", group: "Atomic", trend: "Energy to remove the outermost electron. Peaks at the noble gases, drops sharply at each alkali metal; small dips at B/Al (p¹) and O/S (paired p⁴) reveal subshell structure." },
  electronAffinity: { label: "Electron affinity", unit: "eV", group: "Atomic", trend: "Energy released when a neutral atom gains an electron. Halogens are highest (Cl 3.61 eV); noble gases and Be/Mg/N are near or below zero." },
  polarizability: { label: "Dipole polarisability", unit: "a.u.", group: "Atomic", log: true, trend: "How easily the electron cloud deforms. Large, soft atoms (Cs, Fr) polarise most — the root of London dispersion forces and HSAB 'softness'." },
  melt: { label: "Melting point", unit: "K", group: "Thermal", trend: "Peaks in the middle of the transition series (W 3695 K, the highest metal) where d-band bonding is half filled; low for alkali metals, noble gases and molecular nonmetals." },
  boil: { label: "Boiling point", unit: "K", group: "Thermal", trend: "Tracks cohesive energy: refractory metals boil above 5000 K; helium boils at 4.2 K." },
  liquidRange: { label: "Liquid range", unit: "K", group: "Thermal", trend: "Boiling minus melting point. Gallium stays liquid over ~2200 K — the widest of any element — making it a high-temperature thermometer fluid." },
  heatFusion: { label: "Heat of fusion", unit: "kJ/mol", group: "Thermal", trend: "Energy to melt one mole at the melting point; follows melting temperature roughly (Richards' rule ΔSfus ≈ R for metals)." },
  heatVaporization: { label: "Heat of vaporisation", unit: "kJ/mol", group: "Thermal", trend: "Energy to boil one mole; a direct measure of interatomic bond strength (Trouton's rule ΔSvap ≈ 10.5R)." },
  heatAtomization: { label: "Heat of atomisation", unit: "kJ/mol", group: "Thermal", trend: "Enthalpy to turn the standard state into free gaseous atoms — the cohesive energy. Tungsten and carbon are at the top." },
  specificHeat: { label: "Specific heat", unit: "J/(g·K)", group: "Thermal", trend: "Per gram it falls with atomic weight, because per mole most solids sit near 3R ≈ 25 J/(mol·K) (Dulong–Petit law). Hydrogen and lithium store the most heat per gram." },
  thermalConductivity: { label: "Thermal conductivity", unit: "W/(m·K)", group: "Thermal", log: true, trend: "Metals conduct through free electrons (Ag 429, Cu 401); diamond-carbon conducts via stiff phonons (~2000) despite being an insulator." },
  thermalExpansion: { label: "Thermal expansion", unit: "µm/(m·K)", group: "Thermal", log: true, trend: "Inversely related to melting point: weakly bonded, low-melting metals expand most; W and Mo expand least — why they seal to glass." },
  density: { label: "Density", unit: "g/cm³", group: "Mechanical", trend: "Rises down the table and peaks at osmium/iridium (~22.6 g/cm³), where heavy nuclei sit in tightly packed, lanthanide-contracted lattices." },
  youngsModulus: { label: "Young's modulus", unit: "GPa", group: "Mechanical", log: true, trend: "Elastic stiffness. Highest in the mid-5d metals (Re, Os, Ir, W > 400 GPa) where bonding is strongest; lowest in soft alkali metals." },
  shearModulus: { label: "Shear modulus", unit: "GPa", group: "Mechanical", log: true, trend: "Resistance to shape change; G/B (Pugh ratio) < 0.57 suggests ductile behaviour." },
  bulkModulus: { label: "Bulk modulus", unit: "GPa", group: "Mechanical", log: true, trend: "Resistance to uniform compression; correlates with cohesive energy per volume." },
  poissonRatio: { label: "Poisson's ratio", unit: "", group: "Mechanical", trend: "Lateral contraction per unit stretch. Ductile metals ~0.3–0.45 (gold 0.44); brittle, covalent solids lower (Be 0.03)." },
  mohsHardness: { label: "Mohs hardness", unit: "", group: "Mechanical", trend: "Scratch hardness 1–10. Carbon (diamond) 10, boron 9.5; alkali metals under 1." },
  vickersHardness: { label: "Vickers hardness", unit: "MPa", group: "Mechanical", log: true, trend: "Indentation hardness of the pure element (alloying and work hardening raise it a lot)." },
  brinellHardness: { label: "Brinell hardness", unit: "MPa", group: "Mechanical", log: true, trend: "Ball-indentation hardness, the classic metallurgical test." },
  speedOfSound: { label: "Speed of sound", unit: "m/s", group: "Mechanical", trend: "√(stiffness/density): light, stiff solids (Be 12 900 m/s) carry sound fastest." },
  molarVolume: { label: "Molar volume", unit: "cm³/mol", group: "Mechanical", trend: "Volume of one mole of solid. Lothar Meyer's 1870 plot of this against weight showed periodicity independently of Mendeleev — peaks at each alkali metal." },
  resistivity: { label: "Electrical resistivity", unit: "Ω·m", group: "Electrical & magnetic", log: true, trend: "Spans >20 orders of magnitude: silver is the best conductor (1.6×10⁻⁸ Ω·m); nonmetals such as sulfur are insulators." },
  superconductingTc: { label: "Superconducting Tc", unit: "K", group: "Electrical & magnetic", trend: "Elements that superconduct at ambient pressure; niobium (9.25 K) is highest. Good normal conductors (Cu, Ag, Au) never superconduct." },
  reflectivity: { label: "Reflectivity", unit: "%", group: "Electrical & magnetic", trend: "Visible reflectance of polished metal — silver and aluminium make mirrors." },
  abundanceCrust: { label: "Crustal abundance", unit: "mg/kg", group: "Earth & economy", log: true, trend: "Oxygen and silicon make up ~75% of the crust. Even-Z elements are more abundant than odd neighbours (Oddo–Harkins rule) — a signature of nucleosynthesis." },
  abundanceSea: { label: "Seawater abundance", unit: "mg/L", group: "Earth & economy", log: true, trend: "Dominated by soluble Cl, Na, Mg, S, Ca, K; insoluble metals (Fe, Al) are scarce in seawater despite being common in rock." },
  supplyRisk: { label: "Supply risk (RSC index)", unit: "/10", group: "Earth & economy", trend: "British Geological Survey/RSC index combining scarcity, concentration of production, political stability, recycling and substitutability. Rare earths score highest." },
  pricePerKg: { label: "Price", unit: "USD/kg", group: "Earth & economy", log: true, trend: "Bulk commodity price; spans ~10 orders of magnitude from iron to californium." },
  yearDiscovered: { label: "Year discovered", unit: "", group: "History", trend: "Clusters mark new techniques: electrolysis (1800s), spectroscopy (1860s), liquefied air (1890s), radiochemistry (1900s), accelerators (1940s onward)." },
  isotopesKnown: { label: "Known nuclides", unit: "", group: "Nuclear", trend: "Number of isotopes characterised for the element; mid-weight elements have the most (~40)." },
  stableIsotopes: { label: "Stable isotopes", unit: "", group: "Nuclear", trend: "Tin has 10 stable isotopes (magic Z = 50). Odd-Z elements have at most two; Tc and Pm (Z 43, 61) have none." },
  mendeleevNumber: { label: "Mendeleev number", unit: "", group: "Ordering", trend: "Pettifor-style 1-D ordering that places chemically similar elements next to each other — used to build structure maps in materials discovery." },
  pettiforNumber: { label: "Pettifor number", unit: "", group: "Ordering", trend: "Pettifor's chemical scale (1984): neighbouring numbers ⇒ similar crystal chemistry; 2-D maps of AB compounds by Pettifor number separate structure types cleanly." }
}

export const PROPERTY_GROUPS = [...new Set(Object.values(PROPERTIES).map((p) => p.group))]

export function propertyAccessor(key) {
  if (key === "ionization1") return (el) => el.ionizationEnergies?.[0] ?? null
  if (key === "liquidRange") return (el) => (el.melt != null && el.boil != null && !el.sublimes ? el.boil - el.melt : null)
  if (key === "stableIsotopes") return (el) => el.isotopeSummary?.stable ?? null
  if (key === "density") return (el) => (el.density == null ? null : el.densityUnit === "g/L" ? el.density / 1000 : el.density)
  return (el) => (el[key] ?? null)
}

// Linear (or log) min/max scale over the elements for one property.
// norm(v) maps a value to 0..1, or null when the value is missing/invalid.
export function scale(elements, key, { log = false } = {}) {
  const accessor = propertyAccessor(key)
  const values = elements
    .map(accessor)
    .filter((v) => v != null && Number.isFinite(v) && (!log || v > 0))

  const min = values.length ? Math.min(...values) : 0
  const max = values.length ? Math.max(...values) : 1
  const tMin = log ? Math.log(Math.max(min, Number.EPSILON)) : min
  const tMax = log ? Math.log(Math.max(max, Number.EPSILON)) : max
  const span = tMax - tMin || 1

  return {
    min,
    max,
    count: values.length,
    norm(v) {
      if (v == null || !Number.isFinite(v) || (log && v <= 0)) return null
      const t = log ? Math.log(v) : v
      return Math.min(1, Math.max(0, (t - tMin) / span))
    }
  }
}

export function formatValue(value, unit = "") {
  if (value == null || !Number.isFinite(value)) return "—"
  const abs = Math.abs(value)
  let text
  if (abs !== 0 && (abs < 0.001 || abs >= 1e6)) {
    const [m, e] = value.toExponential(2).split("e")
    text = `${Number(m)}×10${String(Number(e)).replace(/-/g, "⁻").replace(/\d/g, (d) => "⁰¹²³⁴⁵⁶⁷⁸⁹"[d])}`
  } else {
    text = abs >= 100 ? String(Math.round(value)) : String(Number(value.toPrecision(3)))
  }
  return unit ? `${text} ${unit}` : text
}

// ── Classification lenses ─────────────────────────────────────────────
// Each lens: classes { key: { label, color (oklch), desc } }, of(el) → key.
const METALLICITY = {
  "alkali-metal": "metal", "alkaline-earth-metal": "metal", "transition-metal": "metal", "post-transition-metal": "metal",
  lanthanide: "metal", actinide: "metal", metalloid: "metalloid", "reactive-nonmetal": "nonmetal", "noble-gas": "nonmetal"
}

export const LENSES = {
  block: {
    label: "Orbital block",
    explain: "Colour shows which subshell the last electron enters. The table's shape is the shape of quantum mechanics: 2 columns of s, 6 of p, 10 of d, 14 of f.",
    of: (el) => el.block,
    classes: {
      s: { label: "s-block", color: "oklch(70% 0.11 25)", desc: "ns¹–² — reactive metals plus H and He; one or two loosely held electrons." },
      p: { label: "p-block", color: "oklch(70% 0.10 145)", desc: "ns² np¹–⁶ — the most chemically diverse block: metals, metalloids, nonmetals, halogens, noble gases." },
      d: { label: "d-block", color: "oklch(70% 0.09 85)", desc: "(n−1)d¹–¹⁰ — transition metals: variable oxidation states, coloured ions, catalysis, magnetism." },
      f: { label: "f-block", color: "oklch(66% 0.10 330)", desc: "(n−2)f¹–¹⁴ — lanthanides and actinides; buried 4f/5f electrons give near-identical chemistry within a series." }
    }
  },
  metallicity: {
    label: "Metal · metalloid · nonmetal",
    explain: "Metallic character rises toward the lower left. The stair-step line from B to At separates metals from nonmetals, with metalloids straddling it.",
    of: (el) => METALLICITY[el.category] ?? (el.group >= 17 ? "nonmetal" : "metal"),
    classes: {
      metal: { label: "Metal", color: "oklch(68% 0.08 250)", desc: "Lustrous, conductive, malleable; loses electrons to form cations. ~95 of 118 elements." },
      metalloid: { label: "Metalloid", color: "oklch(72% 0.11 75)", desc: "Intermediate: semiconducting B, Si, Ge, As, Sb, Te — the elements of electronics." },
      nonmetal: { label: "Nonmetal", color: "oklch(70% 0.11 150)", desc: "Insulating, brittle or gaseous; gains or shares electrons." }
    }
  },
  goldschmidt: {
    label: "Goldschmidt class",
    explain: "Where an element ends up when a planet differentiates. Iron-loving siderophiles sank to the core, which is why gold and platinum are so rare in the crust.",
    of: (el) => el.goldschmidt || "unknown",
    classes: {
      lithophile: { label: "Lithophile", color: "oklch(72% 0.09 60)", desc: "'Rock-loving' — bonds with oxygen in silicates; concentrated in the crust and mantle (Na, Al, Ti, REE, U)." },
      siderophile: { label: "Siderophile", color: "oklch(64% 0.10 30)", desc: "'Iron-loving' — dissolves in metallic iron; depleted from the crust into the core (Fe, Ni, Co, Au, Pt-group)." },
      chalcophile: { label: "Chalcophile", color: "oklch(72% 0.12 100)", desc: "'Ore-loving' — bonds with sulfur; forms sulfide ore bodies (Cu, Zn, Pb, Ag, Hg, As)." },
      atmophile: { label: "Atmophile", color: "oklch(74% 0.08 220)", desc: "Volatile — lives in the atmosphere and oceans (H, N, noble gases)." },
      synthetic: { label: "Synthetic", color: "oklch(55% 0.02 280)", desc: "Not present in planetary rock in meaningful amounts." },
      unknown: { label: "Unclassified", color: "oklch(45% 0.01 280)", desc: "No assigned class." }
    }
  },
  crystal: {
    label: "Crystal structure",
    explain: "The stable lattice of the solid at ambient conditions. Metallurgy lives here: FCC metals stay ductile when cold; BCC metals have a ductile-to-brittle transition; HCP metals have few slip systems.",
    of: (el) => el.latticeStructure || "unknown",
    classes: {
      FCC: { label: "Face-centred cubic", color: "oklch(72% 0.10 145)", desc: "Close-packed ABC stacking, 12 slip systems — ductile at all temperatures (Al, Cu, Ni, Ag, Au, Pt, Pb)." },
      BCC: { label: "Body-centred cubic", color: "oklch(70% 0.11 40)", desc: "Not close-packed; strong but shows a ductile–brittle transition (α-Fe, Cr, Mo, W, alkali metals)." },
      HEX: { label: "Hexagonal close-packed", color: "oklch(70% 0.10 260)", desc: "Close-packed ABAB stacking with few easy slip systems — anisotropic, harder to form (Mg, Ti, Zn, Co, Zr)." },
      DIA: { label: "Diamond cubic", color: "oklch(76% 0.08 200)", desc: "Tetrahedral covalent network (C, Si, Ge, α-Sn) — the semiconductor lattice." },
      RHL: { label: "Rhombohedral", color: "oklch(70% 0.09 320)", desc: "Distorted layered structures (As, Sb, Bi, B, Hg)." },
      ORC: { label: "Orthorhombic", color: "oklch(70% 0.09 90)", desc: "Three unequal axes at right angles (Ga, S, α-U, Np)." },
      TET: { label: "Tetragonal", color: "oklch(70% 0.09 170)", desc: "Two equal axes (β-Sn, In, Pa)." },
      MCL: { label: "Monoclinic", color: "oklch(66% 0.08 20)", desc: "One oblique angle (Se, α-Pu, O at low T)." },
      CUB: { label: "Simple / complex cubic", color: "oklch(74% 0.06 120)", desc: "Other cubic arrangements (Mn, Po, solid noble gases)." },
      SC: { label: "Simple cubic", color: "oklch(74% 0.06 120)", desc: "One atom per corner — polonium is the only element." },
      unknown: { label: "Unknown", color: "oklch(45% 0.01 280)", desc: "Not determined — too short-lived to crystallise." }
    }
  },
  magnetic: {
    label: "Magnetic ordering",
    explain: "Response to a magnetic field at room temperature. Unpaired d or f electrons give paramagnetism; only Fe, Co, Ni (and Gd just below 20 °C) align spontaneously.",
    of: (el) => el.magnetic?.ordering || "unknown",
    classes: {
      ferro: { label: "Ferromagnetic", color: "oklch(64% 0.15 28)", desc: "Spins align spontaneously into domains below the Curie temperature." },
      antiferro: { label: "Antiferromagnetic", color: "oklch(66% 0.12 300)", desc: "Neighbouring spins align antiparallel below the Néel temperature (Cr)." },
      para: { label: "Paramagnetic", color: "oklch(72% 0.10 80)", desc: "Weakly attracted — unpaired electrons align only in an applied field." },
      dia: { label: "Diamagnetic", color: "oklch(72% 0.07 220)", desc: "Weakly repelled — all electrons paired; induced currents oppose the field (Bi strongest)." },
      unknown: { label: "Unknown", color: "oklch(45% 0.01 280)", desc: "Not measured." }
    }
  },
  bio: {
    label: "Biological role",
    explain: "What life does with each element. About 20 are essential to humans; the dose makes the poison — selenium and copper are essential and toxic within a factor of ~10.",
    of: (el) => el.bio?.role || "none",
    classes: {
      bulk: { label: "Bulk essential", color: "oklch(70% 0.13 145)", desc: "Major structural or ionic components of the body (C H N O P S, Na K Mg Ca Cl)." },
      trace: { label: "Essential trace", color: "oklch(76% 0.11 120)", desc: "Required in small amounts, usually as enzyme cofactors (Fe Zn Cu Mn Co Mo Se I)." },
      beneficial: { label: "Beneficial / some organisms", color: "oklch(76% 0.09 190)", desc: "Used by some organisms or probably beneficial (B, Si, V, Ni, W, Br, lanthanides in bacteria)." },
      none: { label: "No known role", color: "oklch(52% 0.02 280)", desc: "Biologically inert or simply unused." },
      toxic: { label: "Toxic", color: "oklch(62% 0.15 30)", desc: "No role and notable chemical toxicity (Be, As, Cd, Hg, Tl, Pb)." },
      radioactive: { label: "Radiological hazard", color: "oklch(70% 0.14 95)", desc: "No role; radioactive decay is the main hazard." }
    }
  },
  discoveryMethod: {
    label: "How it was found",
    explain: "Every leap in technique unlocked a cluster of elements — chemistry's instruments are written into the table.",
    of: (el) => el.discoveryMethod || "unknown",
    classes: {
      ancient: { label: "Antiquity", color: "oklch(70% 0.10 70)", desc: "Native metals and smelted ores known before written chemistry." },
      chemical: { label: "Chemical isolation", color: "oklch(70% 0.09 40)", desc: "Precipitation, reduction or distillation from compounds." },
      mineral: { label: "Mineral analysis", color: "oklch(70% 0.09 110)", desc: "A new earth or oxide identified in an unusual mineral." },
      electrolysis: { label: "Electrolysis", color: "oklch(72% 0.12 95)", desc: "Davy's voltaic pile freed the reactive alkali and alkaline-earth metals (1807–08)." },
      gas: { label: "Gas chemistry / liquefied air", color: "oklch(74% 0.08 220)", desc: "Pneumatic chemistry and fractional distillation of liquid air." },
      spectroscopy: { label: "Optical spectroscopy", color: "oklch(70% 0.11 290)", desc: "Bunsen and Kirchhoff's spectroscope revealed new lines (Cs, Rb, Tl, In, He…)." },
      xray: { label: "X-ray spectroscopy", color: "oklch(70% 0.10 260)", desc: "Moseley's law (1913) pinpointed the last gaps (Hf, Re)." },
      radiochemistry: { label: "Radiochemistry", color: "oklch(72% 0.13 140)", desc: "Followed radioactivity through chemical separations (Po, Ra, Rn, Ac, Fr, Pm)." },
      synthesis: { label: "Nuclear synthesis", color: "oklch(64% 0.13 20)", desc: "Made in reactors and accelerators — Tc onward." },
      debris: { label: "Thermonuclear debris", color: "oklch(60% 0.14 0)", desc: "Found in fallout of the 1952 Ivy Mike H-bomb test (Es, Fm)." },
      unknown: { label: "Unknown", color: "oklch(45% 0.01 280)", desc: "" }
    }
  }
}

// ── Display modes (toolbar) ───────────────────────────────────────────
export const MODES = [
  { key: "series", label: "Series", group: "Classify", explain: "Chemical families. Elements in a column share outer-electron structure and therefore chemistry; rows (periods) add one electron shell each." },
  { key: "block", label: "Blocks", group: "Classify", lens: "block" },
  { key: "metallicity", label: "Metallicity", group: "Classify", lens: "metallicity" },
  { key: "crystal", label: "Crystal", group: "Classify", lens: "crystal" },
  { key: "magnetic", label: "Magnetism", group: "Classify", lens: "magnetic" },
  { key: "goldschmidt", label: "Geochem", group: "Classify", lens: "goldschmidt" },
  { key: "bio", label: "Biology", group: "Classify", lens: "bio" },
  { key: "trends", label: "Trends", group: "Measure", explain: "Heat map of the chosen property. Pick any of 40 properties — the note under the scale explains the pattern." },
  { key: "state", label: "State", group: "Explore", explain: "Solid, liquid or gas at the chosen temperature (at 1 atm). Drag the slider: only Hg and Br are liquid at room temperature; Cs and Ga melt in your hand." },
  { key: "discovery", label: "Discovery", group: "Explore", explain: "Elements known by the chosen year. Play the timeline to watch techniques unlock clusters of elements; colours show how each was found." },
  { key: "electrons", label: "Electrons", group: "Explore", explain: "Ground-state electron configuration. Exceptions to the Aufbau order (Cr, Cu, Nb, Mo, Ru, Rh, Pd, Ag, Pt, Au…) favour half- or fully-filled d subshells." },
  { key: "oxidation", label: "Oxidation", group: "Explore", explain: "Main oxidation states (bold) and others observed. Transition metals span many states; fluorine only ever −1; osmium and xenon reach +8." },
  { key: "valence", label: "Valence", group: "Explore", explain: "Valence (outer) electrons available for bonding — the number behind the octet rule for main-group elements." },
  { key: "isotopes", label: "Isotopes", group: "Explore", explain: "Number of stable isotopes. Even Z and N favour stability; nothing beyond lead (Z 82) is truly stable." }
]

// Phase at a given temperature (K), from STP melt/boil points.
export function stateAt(el, tempK) {
  if (tempK == null) return "unknown"
  const { melt, boil } = el
  if (melt == null && boil == null) return "unknown"
  if (el.sublimes && boil != null) return tempK >= boil ? "gas" : "solid"
  if (melt != null && tempK < melt) return "solid"
  if (boil != null && tempK >= boil) return "gas"
  if (melt != null) return "liquid"
  return "unknown"
}

// Was this element known by the given year? Ancient elements are always known.
export function knownBy(el, year) {
  if (el.ancient) return el.earliestUse == null || el.earliestUse <= year
  if (el.yearDiscovered == null) return false
  return el.yearDiscovered <= year
}

export function formatTemp(k, unit) {
  if (k == null || !Number.isFinite(k)) return "—"
  if (unit === "C") return `${Math.round(k - 273.15)} °C`
  if (unit === "F") return `${Math.round(((k - 273.15) * 9) / 5 + 32)} °F`
  return `${Math.round(k)} K`
}
