import test from "node:test";
import assert from "node:assert/strict";
import { ELEMENTS, CATEGORIES, SOURCES } from "../../app/javascript/lib/periodic_table/elements.mjs";
import { ELEMENT_DETAILS } from "../../app/javascript/lib/periodic_table/element_details.mjs";
import { NUCLIDES } from "../../app/javascript/lib/periodic_table/nuclides.mjs";
import { LAND_PATH } from "../../app/javascript/lib/periodic_table/world.mjs";

test("ELEMENTS has exactly 118 records sorted by atomic number", () => {
  assert.equal(ELEMENTS.length, 118);
  for (let i = 0; i < ELEMENTS.length; i++) {
    assert.equal(ELEMENTS[i].number, i + 1);
  }
});

test("atomic numbers and symbols are unique", () => {
  assert.equal(new Set(ELEMENTS.map((e) => e.number)).size, 118);
  assert.equal(new Set(ELEMENTS.map((e) => e.symbol)).size, 118);
});

test("every element's category is a valid CATEGORIES key", () => {
  const keys = new Set(Object.keys(CATEGORIES));
  for (const e of ELEMENTS) {
    assert.ok(keys.has(e.category), `${e.symbol} has unknown category "${e.category}"`);
  }
});

test("SOURCES lists attribution entries with name/url/license", () => {
  assert.ok(Array.isArray(SOURCES) && SOURCES.length > 0);
  for (const s of SOURCES) {
    assert.equal(typeof s.name, "string");
    assert.equal(typeof s.url, "string");
    assert.equal(typeof s.license, "string");
  }
});

test("xpos/ypos and wxpos/wypos are within the periodic table grid", () => {
  for (const e of ELEMENTS) {
    assert.ok(e.xpos >= 1 && e.xpos <= 18, `${e.symbol} xpos out of range: ${e.xpos}`);
    assert.ok(e.ypos >= 1 && e.ypos <= 10, `${e.symbol} ypos out of range: ${e.ypos}`);
    assert.ok(e.wxpos >= 1 && e.wxpos <= 32, `${e.symbol} wxpos out of range: ${e.wxpos}`);
    assert.ok(e.wypos >= 1 && e.wypos <= 10, `${e.symbol} wypos out of range: ${e.wypos}`);
  }
});

test("group is null only for the lanthanide/actinide f-block row", () => {
  for (const e of ELEMENTS) {
    if (e.category === "lanthanide" || e.category === "actinide") {
      assert.equal(e.group, null, `${e.symbol} (${e.category}) should have null group`);
    } else {
      assert.notEqual(e.group, null, `${e.symbol} should have a group`);
    }
  }
});

test("shells sum to the atomic number (total electron count)", () => {
  for (const e of ELEMENTS) {
    const sum = e.shells.reduce((a, b) => a + b, 0);
    assert.equal(sum, e.number, `${e.symbol} shells ${JSON.stringify(e.shells)} sum to ${sum}, expected ${e.number}`);
  }
});

test("natural isotope abundances sum to ~100% where abundance data exists", () => {
  for (const e of ELEMENTS) {
    const natural = ELEMENT_DETAILS[e.number].isotopes.filter((iso) => iso.abundance > 0);
    if (natural.length === 0) continue;
    const sum = natural.reduce((a, iso) => a + iso.abundance, 0);
    assert.ok(
      Math.abs(sum - 100) < 1,
      `${e.symbol} natural isotope abundances sum to ${sum}, expected ~100`
    );
  }
});

test("ancient elements have ancient:true and no yearDiscovered", () => {
  const ancientSymbols = ["C", "S", "Fe", "Cu", "Ag", "Sn", "Au", "Hg", "Pb", "Sb", "Zn"];
  for (const sym of ancientSymbols) {
    const e = ELEMENTS.find((x) => x.symbol === sym);
    assert.equal(e.ancient, true, `${sym} should be marked ancient`);
    assert.equal(e.yearDiscovered, null, `${sym} should have null yearDiscovered`);
  }
});

test("spot check: mercury is liquid at STP", () => {
  const hg = ELEMENTS.find((e) => e.symbol === "Hg");
  assert.equal(hg.phase, "liquid");
  assert.equal(hg.number, 80);
});

test("spot check: oxygen is gas at STP with g/L density", () => {
  const o = ELEMENTS.find((e) => e.symbol === "O");
  assert.equal(o.phase, "gas");
  assert.equal(o.densityUnit, "g/L");
  assert.ok(o.density > 0 && o.density < 10, `O density ${o.density} looks wrong for g/L`);
});

test("spot check: iron melts around 1811K and is a transition metal", () => {
  const fe = ELEMENTS.find((e) => e.symbol === "Fe");
  assert.equal(fe.category, "transition-metal");
  assert.ok(Math.abs(fe.melt - 1811) < 5, `Fe melt ${fe.melt}, expected ~1811K`);
  assert.equal(fe.phase, "solid");
});

test("standard atomic weights replace conventional integers (Li is 6.94, not 7)", () => {
  const li = ELEMENTS.find((e) => e.symbol === "Li");
  assert.equal(li.atomicWeight, 6.94);
  assert.equal(li.mass, 6.94);
  const tc = ELEMENTS.find((e) => e.symbol === "Tc");
  assert.equal(tc.atomicWeightBracketed, true);
});

test("discovery history is corrected and geolocated for every element", () => {
  for (const e of ELEMENTS) {
    assert.ok(Number.isFinite(e.discoveryLat) && Number.isFinite(e.discoveryLon), `${e.symbol} lacks coordinates`);
    assert.ok(e.discoveryMethod, `${e.symbol} lacks discovery method`);
    if (!e.ancient) assert.ok(Number.isInteger(e.yearDiscovered), `${e.symbol} lacks a discovery year`);
  }
  const f = ELEMENTS.find((e) => e.symbol === "F");
  assert.equal(f.yearDiscovered, 1886);
  assert.match(f.discoveredBy, /Moissan/);
  assert.equal(ELEMENTS.find((e) => e.symbol === "Al").yearDiscovered, 1825);
});

test("every element has a biological role and magnetic ordering", () => {
  const roles = new Set(["bulk", "trace", "beneficial", "none", "toxic", "radioactive"]);
  for (const e of ELEMENTS) {
    assert.ok(roles.has(e.bio?.role), `${e.symbol} bio role ${e.bio?.role}`);
    assert.ok(e.magnetic?.ordering, `${e.symbol} magnetic ordering missing`);
  }
  assert.equal(ELEMENTS.find((e) => e.symbol === "Fe").magnetic.ordering, "ferro");
});

test("Shannon radii, oxidation states and mechanical data are present for iron", () => {
  const fe = ELEMENTS.find((e) => e.symbol === "Fe");
  assert.deepEqual(fe.oxidationMain, [3, 2]);
  assert.ok(fe.youngsModulus > 150 && fe.youngsModulus < 250);
  assert.equal(fe.latticeStructure, "BCC");
  const radii = ELEMENT_DETAILS[26].ionicRadii;
  assert.ok(radii.some(([charge, cn, spin]) => charge === 2 && cn === "VI" && spin === "HS"));
});

test("isotope half-lives never show resonance widths as times", () => {
  for (const d of Object.values(ELEMENT_DETAILS)) {
    for (const iso of d.isotopes) {
      if (iso.halfLife) assert.doesNotMatch(iso.halfLife, /^[\d.]+ (MeV|keV|eV)$/);
    }
  }
});

test("nuclide chart covers the known nuclides with stable ones flagged", () => {
  assert.ok(NUCLIDES.length > 3000);
  const stable = NUCLIDES.filter((r) => r[2] === -1);
  assert.ok(stable.length >= 240 && stable.length <= 300, `stable count ${stable.length}`);
  assert.ok(NUCLIDES.some(([z, n]) => z === 26 && n === 30));
  assert.match(LAND_PATH, /^M[\d.]+ [\d.]+L/);
});

test("ionisation series are physical: 1st IE ≤ He's 24.6 eV and strictly increasing", () => {
  for (const e of ELEMENTS) {
    const ie = e.ionizationEnergies;
    if (!ie.length) continue;
    assert.ok(ie[0] <= 24.6, `${e.symbol} 1st IE ${ie[0]} eV`);
    for (let i = 1; i < ie.length; i++) assert.ok(ie[i] > ie[i - 1], `${e.symbol} IE${i + 1} not increasing`);
  }
});

test("isotope exact masses keep full precision", () => {
  const fe54 = ELEMENT_DETAILS[26].isotopes.find((i) => i.mass === 54);
  assert.equal(fe54.exactMass, 53.9396082);
});
