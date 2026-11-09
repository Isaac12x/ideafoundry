import test from "node:test"
import assert from "node:assert/strict"
import { convert, nextUnit, format } from "../../app/javascript/lib/ingredient_units.mjs"

test("converts metric and imperial", () => {
  assert.equal(format(convert(100, "g", "oz")), "3.53")
  assert.equal(format(convert(1, "lb", "g")), "454")
  assert.equal(format(convert(1, "cup", "ml")), "237")
  assert.equal(format(convert(2, "tbsp", "tsp")), "6")
})

test("cycles within a family and wraps", () => {
  assert.equal(nextUnit("g"), "kg")
  assert.equal(nextUnit("lb"), "g")
  assert.equal(nextUnit("fl oz"), "ml")
})
