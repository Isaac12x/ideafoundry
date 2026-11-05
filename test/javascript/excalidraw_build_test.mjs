import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

// A failed Excalidraw build must leave the previously published build (manifest + files) untouched.
test("failed build keeps the published manifest", () => {
  const root = process.cwd()
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "excalidraw-build-"))
  try {
    fs.symlinkSync(path.join(root, "node_modules"), path.join(tmp, "node_modules"))
    fs.copyFileSync(path.join(root, "esbuild.config.mjs"), path.join(tmp, "esbuild.config.mjs"))
    fs.mkdirSync(path.join(tmp, "tmp"))
    fs.mkdirSync(path.join(tmp, "app/javascript"), { recursive: true })
    for (const name of fs.readdirSync(path.join(root, "app/javascript"))) {
      if (name !== "excalidraw_app") fs.symlinkSync(path.join(root, "app/javascript", name), path.join(tmp, "app/javascript", name))
    }
    fs.mkdirSync(path.join(tmp, "app/javascript/excalidraw_app"))
    fs.writeFileSync(path.join(tmp, "app/javascript/excalidraw_app/index.tsx"), "export const = ;\n")

    const version = JSON.parse(fs.readFileSync(path.join(root, "node_modules/@excalidraw/excalidraw/package.json"), "utf8")).version
    const dir = path.join(tmp, "public/excalidraw-assets", version)
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(path.join(dir, "manifest.json"), '{"js":"index-OLD.js"}')
    fs.writeFileSync(path.join(dir, "index-OLD.js"), "old")

    const result = runBuild(tmp)
    assert.notEqual(result.status, 0, "broken build must exit non-zero")
    assert.match(result.stderr, /ERROR/, result.stderr) // failed in esbuild, not elsewhere
    assert.equal(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"), '{"js":"index-OLD.js"}')
    assert.equal(fs.readFileSync(path.join(dir, "index-OLD.js"), "utf8"), "old")
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})

import { spawnSync } from "node:child_process"
function runBuild(cwd) {
  return spawnSync(process.execPath, ["esbuild.config.mjs", "--dev"], { cwd, encoding: "utf8" })
}
