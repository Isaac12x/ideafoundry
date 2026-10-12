import test from "node:test";
import assert from "node:assert/strict";
import { ELEMENTS } from "../../app/javascript/lib/periodic_table/elements.mjs";
import { COMPOUNDS, FORMULA_ALIASES, ALLOYS } from "../../app/javascript/lib/periodic_table/compounds.mjs";
import {
  ChemError, indexElements, parseFormula, hillFormula, formulaHTML, molarMass, composition,
  empiricalFromPercent, balanceEquation, stoichiometry, predictBinaries, bondCharacter,
  wtToAt, atToWt, alloyMetrics, humeRothery, vecOf
} from "../../app/javascript/lib/periodic_table/chem.mjs";

const idx = indexElements(ELEMENTS);
const el = (s) => idx.get(s);
const counts = (f) => Object.fromEntries(parseFormula(f, idx).counts);
const close = (a, b, tol = 0.01) => assert.ok(Math.abs(a - b) <= tol, `${a} ≉ ${b}`);

test("parses nested groups, brackets and hydrates", () => {
  assert.deepEqual(counts("Ca(OH)2"), { Ca: 1, O: 2, H: 2 });
  assert.deepEqual(counts("K4[Fe(CN)6]"), { K: 4, Fe: 1, C: 6, N: 6 });
  assert.deepEqual(counts("CuSO4·5H2O"), { Cu: 1, S: 1, O: 9, H: 10 });
  assert.deepEqual(counts("CuSO4.5H2O"), { Cu: 1, S: 1, O: 9, H: 10 });
  assert.deepEqual(counts("Li0.5CoO2"), { Li: 0.5, Co: 1, O: 2 });
  assert.deepEqual(counts("(NH4)2SO4"), { N: 2, H: 8, S: 1, O: 4 });
});

test("distinguishes Co from CO and rejects unknown symbols with a position", () => {
  assert.deepEqual(counts("Co"), { Co: 1 })
  assert.deepEqual(counts("CO"), { C: 1, O: 1 })
  assert.throws(() => parseFormula("Xy2", idx), (e) => e instanceof ChemError && /Unknown element 'X'/.test(e.message))
  assert.throws(() => parseFormula("Ca(OH", idx), ChemError)
  assert.throws(() => parseFormula("CaOH)", idx), ChemError)
});

test("parses ionic charge suffixes", () => {
  assert.equal(parseFormula("SO4^2-", idx).charge, -2)
  assert.equal(parseFormula("Fe^3+", idx).charge, 3)
  assert.equal(parseFormula("NH4^+", idx).charge, 1)
});

test("Hill notation orders C, H, then alphabetical", () => {
  assert.equal(hillFormula(parseFormula("CH3COOH", idx).counts), "C2H4O2")
  assert.equal(hillFormula(parseFormula("H2SO4", idx).counts), "H2O4S")
  assert.equal(hillFormula(parseFormula("NaCl", idx).counts), "ClNa")
});

test("formulaHTML subscripts counts and superscripts charges", () => {
  assert.equal(formulaHTML("Fe2O3"), "Fe<sub>2</sub>O<sub>3</sub>")
  assert.equal(formulaHTML("SO4^2-"), "SO<sub>4</sub><sup>2−</sup>")
});

test("molar masses match reference values", () => {
  close(molarMass(parseFormula("H2O", idx).counts, idx).mass, 18.015)
  close(molarMass(parseFormula("NaCl", idx).counts, idx).mass, 58.44)
  close(molarMass(parseFormula("C6H12O6", idx).counts, idx).mass, 180.156, 0.02)
  close(molarMass(parseFormula("CuSO4·5H2O", idx).counts, idx).mass, 249.68, 0.02)
});

test("composition mass percents sum to 100", () => {
  const comp = composition(parseFormula("Fe2O3", idx).counts, idx)
  close(comp.reduce((a, c) => a + c.massPct, 0), 100, 1e-9)
  close(comp.find((c) => c.symbol === "Fe").massPct, 69.94, 0.02)
});

test("empirical formula from mass percent", () => {
  const glucose = empiricalFromPercent({ C: 40.0, H: 6.71, O: 53.29 }, idx)
  assert.deepEqual(Object.fromEntries(glucose.counts), { C: 1, H: 2, O: 1 })
  const hematite = empiricalFromPercent({ Fe: 69.94, O: 30.06 }, idx)
  assert.deepEqual(Object.fromEntries(hematite.counts), { Fe: 2, O: 3 })
});

test("balances molecular, redox and ionic equations", () => {
  const coeff = (eq) => balanceEquation(eq, idx).species.map((s) => s.coefficient)
  assert.deepEqual(coeff("Fe + O2 -> Fe2O3"), [4, 3, 2])
  assert.deepEqual(coeff("C3H8 + O2 -> CO2 + H2O"), [1, 5, 3, 4])
  assert.deepEqual(coeff("KMnO4 + HCl -> KCl + MnCl2 + H2O + Cl2"), [2, 16, 2, 2, 8, 5])
  assert.deepEqual(coeff("MnO4^- + Fe^2+ + H^+ -> Mn^2+ + Fe^3+ + H2O"), [1, 5, 8, 1, 5, 4])
  assert.deepEqual(coeff("Cu^2+ + e -> Cu"), [1, 2, 1])
  assert.deepEqual(coeff("CuSO4·5H2O -> CuSO4 + H2O"), [1, 1, 5])
});

test("balancer reports impossible and ambiguous equations", () => {
  assert.throws(() => balanceEquation("H2 -> O2", idx), ChemError)
  assert.throws(() => balanceEquation("H2 + O2 -> H2O + H2O2", idx), /independent reactions/)
});

test("stoichiometry picks the limiting reagent", () => {
  const { species } = balanceEquation("2H2 + O2 -> 2H2O", idx)
  const result = stoichiometry(species, { 0: 4.0, 1: 64.0 })
  assert.equal(result.limiting, 0)
  close(result.rows[2].grams, 35.74, 0.02) // 4 g H2 = 1.984 mol
});

test("predicts charge-balanced binaries with IUPAC names", () => {
  const ironOxides = predictBinaries(el("Fe"), el("O")).map((c) => `${c.formula}=${c.name}`)
  assert.ok(ironOxides.includes("FeO=iron(II) oxide"))
  assert.ok(ironOxides.includes("Fe2O3=iron(III) oxide"))
  assert.deepEqual(predictBinaries(el("Al"), el("O")).map((c) => c.formula), ["Al2O3"])
  assert.deepEqual(predictBinaries(el("Na"), el("Cl")).map((c) => c.name), ["sodium chloride"])
  const sulfurOxides = predictBinaries(el("S"), el("O")).map((c) => `${c.formula}=${c.name}`)
  assert.ok(sulfurOxides.includes("SO3=sulfur trioxide"))
  assert.ok(sulfurOxides.includes("SO2=sulfur dioxide"))
  const pcl = predictBinaries(el("P"), el("Cl")).map((c) => c.name)
  assert.ok(pcl.includes("phosphorus pentachloride"))
});

test("bond character follows Pauling electronegativity difference", () => {
  assert.equal(bondCharacter(el("Na"), el("Cl")).kind, "ionic")
  assert.equal(bondCharacter(el("H"), el("Cl")).kind, "polar covalent")
  assert.equal(bondCharacter(el("C"), el("H")).kind, "nonpolar covalent")
  assert.equal(bondCharacter(el("Cu"), el("Zn")).kind, "metallic")
});

test("wt% ↔ at% conversions round-trip", () => {
  const at = wtToAt({ Cu: 70, Zn: 30 }, idx)
  close(at.Cu, 70.6, 0.1)
  const back = atToWt(at, idx)
  close(back.Cu, 70, 1e-9)
  // Nitinol: 55 wt% Ni is ~50 at% Ni.
  close(wtToAt({ Ni: 55, Ti: 45 }, idx).Ni, 50, 1)
});

test("alloy metrics: equiatomic Cantor alloy is high-entropy FCC", () => {
  const m = alloyMetrics({ Co: 20, Cr: 20, Fe: 20, Mn: 20, Ni: 20 }, idx)
  close(m.deltaSmixR, Math.log(5), 1e-9)
  assert.equal(m.entropyClass, "high-entropy")
  close(m.vec, 8.0, 1e-9)
  assert.match(m.phase, /FCC/)
  assert.ok(m.delta < 6.6)
  assert.ok(m.density > 7.5 && m.density < 8.5)
});

test("VEC per element and Hume-Rothery for Cu–Ni vs Cu–Pb", () => {
  assert.equal(vecOf(el("Fe")), 8)
  assert.equal(vecOf(el("Al")), 3)
  assert.equal(humeRothery(el("Cu"), el("Ni")).verdict, "Extensive solid solubility likely")
  assert.notEqual(humeRothery(el("Cu"), el("Pb")).verdict, "Extensive solid solubility likely")
});

test("every curated compound parses and has a sane molar mass", () => {
  for (const [formula, name] of COMPOUNDS) {
    const f = FORMULA_ALIASES[formula] ?? formula
    const { counts: c } = parseFormula(f, idx)
    const m = molarMass(c, idx).mass
    assert.ok(m > 1 && m < 5000, `${name} (${formula}) molar mass ${m}`)
  }
});

test("curated compound formulas are unique", () => {
  const seen = new Set()
  for (const [formula] of COMPOUNDS) {
    assert.ok(!seen.has(formula), `duplicate compound ${formula}`)
    seen.add(formula)
  }
});

test("every alloy uses real elements and sums to ~100 wt%", () => {
  for (const [name, comp] of ALLOYS) {
    for (const s of Object.keys(comp)) assert.ok(idx.has(s), `${name}: unknown ${s}`)
    const sum = Object.values(comp).reduce((a, b) => a + b, 0)
    assert.ok(Math.abs(sum - 100) < 0.6, `${name} sums to ${sum}`)
  }
});
