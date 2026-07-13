import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("shortcut hint keys are deterministic and compact", async () => {
  const ShortcutsController = await loadShortcutsController();

  assert.equal(ShortcutsController.hintForIndex(0), "a");
  assert.equal(ShortcutsController.hintForIndex(1), "s");
  assert.equal(ShortcutsController.hintForIndex(35), "0");
  assert.equal(ShortcutsController.hintForIndex(36), "aa");
  assert.equal(ShortcutsController.hintForIndex(37), "as");
});

test("shortcut labels are normalized for cheatsheet display", async () => {
  const ShortcutsController = await loadShortcutsController();
  const controller = new ShortcutsController();

  assert.equal(controller.cleanLabel("  Save\n\nCurrent\tIdea  "), "Save Current Idea");
});

async function loadShortcutsController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/shortcuts_controller.js", import.meta.url),
    "utf8"
  );
  const runnableSource = source
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller", "return class ShortcutsController extends Controller");

  return new Function("Controller", runnableSource)(class {});
}
