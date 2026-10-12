import test from "node:test"
import assert from "node:assert/strict"
import { scale, stateAt, knownBy, formatTemp } from "../../app/javascript/lib/periodic_table/trends.mjs"

const Hg = { number: 80, symbol: "Hg", melt: 234.32, boil: 629.88 }
const Fe = { number: 26, symbol: "Fe", melt: 1811, boil: 3134 }
const O = { number: 8, symbol: "O", melt: 54.36, boil: 90.2 }
const He = { number: 2, symbol: "He", melt: null, boil: null }

test("stateAt: Hg at 298K is liquid", () => {
  assert.equal(stateAt(Hg, 298), "liquid")
})

test("stateAt: Fe at 298K is solid", () => {
  assert.equal(stateAt(Fe, 298), "solid")
})

test("stateAt: O at 298K is gas", () => {
  assert.equal(stateAt(O, 298), "gas")
})

test("stateAt: Fe at 2000K is liquid", () => {
  assert.equal(stateAt(Fe, 2000), "liquid")
})

test("stateAt: unknown melt/boil is unknown", () => {
  assert.equal(stateAt(He, 298), "unknown")
})

test("scale: norm bounds and missing values", () => {
  const elements = [{ mass: 1 }, { mass: 5 }, { mass: 10 }, { mass: null }]
  const s = scale(elements, "mass")
  assert.equal(s.min, 1)
  assert.equal(s.max, 10)
  assert.equal(s.norm(1), 0)
  assert.equal(s.norm(10), 1)
  assert.equal(s.norm(5), (5 - 1) / (10 - 1))
  assert.equal(s.norm(null), null)
})

test("scale: log scale ignores non-positive values", () => {
  const elements = [{ abundanceCrust: 1 }, { abundanceCrust: 100 }, { abundanceCrust: 0 }]
  const s = scale(elements, "abundanceCrust", { log: true })
  assert.equal(s.min, 1)
  assert.equal(s.max, 100)
  assert.equal(s.norm(0), null)
  assert.ok(s.norm(10) > 0 && s.norm(10) < 1)
})

test("knownBy: ancient elements are always known", () => {
  assert.equal(knownBy({ ancient: true, yearDiscovered: null }, -5000), true)
})

test("knownBy: gated on yearDiscovered vs. year", () => {
  const el = { yearDiscovered: 1898 }
  assert.equal(knownBy(el, 1897), false)
  assert.equal(knownBy(el, 1898), true)
  assert.equal(knownBy(el, 2000), true)
})

test("knownBy: unknown discovery year defaults to unknown (false)", () => {
  assert.equal(knownBy({ yearDiscovered: null }, 2010), false)
})

test("formatTemp: K, C, F conversions", () => {
  assert.equal(formatTemp(298, "K"), "298 K")
  assert.equal(formatTemp(298, "C"), "25 °C")
  assert.equal(formatTemp(298, "F"), "77 °F")
  assert.equal(formatTemp(null, "K"), "—")
})
