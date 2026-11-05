import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const index = readFileSync("app/javascript/controllers/index.js", "utf8")

// A lazily imported controller does not hear keys pressed in the first moments of a page: the lock one must not be lazy.
test("typing-activity is registered statically, before the lazy loader runs", () => {
  assert.match(index, /^import TypingActivityController from "controllers\/typing_activity_controller"/m)
  const register = index.indexOf('application.register("typing-activity"')
  const loader = index.indexOf('eagerLoadControllersFrom("controllers"')
  assert.ok(register > 0 && register < loader, "registered after (or without) the loader")
})
