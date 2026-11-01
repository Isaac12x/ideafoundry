import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"

const pins = readFileSync("config/importmap.rb", "utf8")
const dir = "app/javascript/controllers"

test("every bare lib/* import in controllers has an importmap pin", () => {
  const missing = []
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".js"))) {
    for (const [, mod] of readFileSync(`${dir}/${f}`, "utf8").matchAll(/(?:from\s+|import\()\s*["'](lib\/[^"']+)["']/g)) {
      if (!pins.includes(`pin "${mod}"`)) missing.push(`${f}: ${mod}`)
    }
  }
  assert.deepEqual(missing, [])
})
