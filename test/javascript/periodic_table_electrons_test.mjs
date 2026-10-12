import test from "node:test";
import assert from "node:assert/strict";
import {
  expandConfig,
  parseConfig,
  orbitalBoxes,
  shellsFromConfig,
  valenceFromRecord,
  bohrSVG,
} from "../../app/javascript/lib/periodic_table/electrons.mjs";

// Local fixtures (the real data file is owned by another agent and built in
// parallel) — just enough of the schema for Fe, Cu, U to exercise the math.
const FE = {
  number: 26,
  symbol: "Fe",
  electronConfig: "[Ar] 3d6 4s2",
  electronConfigFull: "1s2 2s2 2p6 3s2 3p6 3d6 4s2",
  shells: [2, 8, 14, 2],
  valence: 2,
};

const CU = {
  number: 29,
  symbol: "Cu",
  electronConfig: "[Ar] 3d10 4s1", // Aufbau exception
  electronConfigFull: "1s2 2s2 2p6 3s2 3p6 3d10 4s1",
  shells: [2, 8, 18, 1],
  valence: 1,
};

const U = {
  number: 92,
  symbol: "U",
  electronConfig: "[Rn] 5f3 6d1 7s2", // Aufbau exception
  electronConfigFull:
    "1s2 2s2 2p6 3s2 3p6 3d10 4s2 4p6 4d10 4f14 5d10 5s2 5p6 6s2 6p6 5f3 6d1 7s2",
  shells: [2, 8, 18, 32, 21, 9, 2],
  valence: null,
};

const NA = {
  number: 11,
  symbol: "Na",
  electronConfig: "[Ne] 3s1",
  electronConfigFull: "1s2 2s2 2p6 3s1",
  shells: [2, 8, 1],
  valence: 1,
};

test("expandConfig resolves noble-gas cores", () => {
  assert.equal(expandConfig(FE.electronConfig), FE.electronConfigFull);
  assert.equal(expandConfig(CU.electronConfig), CU.electronConfigFull);
  assert.equal(expandConfig(U.electronConfig), U.electronConfigFull);
});

test("expandConfig is a no-op / normalizes when there is no core", () => {
  assert.equal(expandConfig("1s2   2s2"), "1s2 2s2");
  assert.equal(expandConfig(""), "");
});

test("parseConfig + shellsFromConfig cross-check record.shells for Fe, Cu, U", () => {
  for (const el of [FE, CU, U, NA]) {
    const parsed = parseConfig(expandConfig(el.electronConfig));
    const shells = shellsFromConfig(parsed);
    assert.deepEqual(shells, el.shells, `${el.symbol} shells mismatch`);
    assert.equal(
      shells.reduce((a, b) => a + b, 0),
      el.number,
      `${el.symbol} total electrons should equal atomic number`
    );
  }
});

test("Cu and U aufbau exceptions parse as written (not aufbau order)", () => {
  const cuParsed = parseConfig(expandConfig(CU.electronConfig));
  const last = cuParsed[cuParsed.length - 1];
  assert.deepEqual(last, { n: 4, l: "s", electrons: 1 });

  const uParsed = parseConfig(expandConfig(U.electronConfig));
  const tail = uParsed.slice(-3);
  assert.deepEqual(tail, [
    { n: 5, l: "f", electrons: 3 },
    { n: 6, l: "d", electrons: 1 },
    { n: 7, l: "s", electrons: 2 },
  ]);
});

test("valenceFromRecord prefers the record's own valence", () => {
  assert.equal(valenceFromRecord(FE), 2);
  assert.equal(valenceFromRecord(CU), 1);
});

test("valenceFromRecord derives from config when valence is null", () => {
  // U: valence null in fixture -> derive from highest-n subshells (7s2 -> 2)
  assert.equal(valenceFromRecord(U), 2);
});

test("orbitalBoxes applies Hund's rule for O 2p4 (up-down, up, up)", () => {
  const parsed = parseConfig("1s2 2s2 2p4");
  const boxes = orbitalBoxes(parsed);
  const p = boxes.find((s) => s.label === "2p");
  assert.deepEqual(
    p.boxes.map((b) => [b.up, b.down]),
    [
      [true, true],
      [true, false],
      [true, false],
    ]
  );
});

test("orbitalBoxes applies Hund's rule for N 2p3 (up, up, up)", () => {
  const parsed = parseConfig("1s2 2s2 2p3");
  const boxes = orbitalBoxes(parsed);
  const p = boxes.find((s) => s.label === "2p");
  assert.deepEqual(
    p.boxes.map((b) => [b.up, b.down]),
    [
      [true, false],
      [true, false],
      [true, false],
    ]
  );
});

test("bohrSVG renders the correct number of electron dots for Na (11)", () => {
  const svg = bohrSVG(NA.shells, { symbol: "Na", size: 200 });
  const dotCount = (svg.match(/class="ptd-electron/g) || []).length;
  assert.equal(dotCount, 11);
  assert.equal(NA.shells.reduce((a, b) => a + b, 0), 11);

  // Valence shell (last, single 3s electron) should be highlighted.
  const valenceCount = (svg.match(/class="ptd-electron is-valence"/g) || []).length;
  assert.equal(valenceCount, 1);
});

test("bohrSVG escapes the symbol and is deterministic across calls", () => {
  const a = bohrSVG(FE.shells, { symbol: "Fe", size: 220 });
  const b = bohrSVG(FE.shells, { symbol: "Fe", size: 220 });
  assert.equal(a, b);
  assert.match(a, /Bohr model of Fe/);
});
