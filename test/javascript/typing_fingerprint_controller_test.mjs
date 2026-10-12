import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("accuracy drops on a mistake and stays down after it is corrected", async () => {
  const controller = await buildController("hello");

  type(controller, "hel");
  assert.equal(controller.accuracy(), 100);

  type(controller, "helz");
  assert.equal(controller.accuracy(), 75);

  type(controller, "hel"); // backspace
  type(controller, "hell");
  assert.equal(controller.accuracy(), 80);

  type(controller, "hello");
  assert.equal(controller.accuracy(), 83);
});

test("accuracy starts at 100% before anything is typed", async () => {
  const controller = await buildController("hello");

  assert.equal(controller.accuracy(), 100);
});

test("a capital letter closes even when Shift is released before the letter", async () => {
  const controller = await buildController("A");
  controller.activateKey = () => {};
  controller.deactivateKey = () => {};
  controller.lastKeyTarget = { textContent: "" };
  controller.startTicking = () => {};

  controller.keydown({ key: "A", code: "KeyA" });
  type(controller, "A");
  controller.keyup({ key: "a", code: "KeyA" });

  assert.equal(controller.pending.some((event) => event.up === undefined), false);
  assert.equal(controller.events.length, 1);
});

// Drives input() the way the textarea does: set the value, then fire.
function type(controller, value) {
  controller.inputTarget.value = value;
  controller.input();
}

async function buildController(text) {
  const TypingFingerprintController = await loadController();
  const controller = new TypingFingerprintController();

  controller.textValue = text;
  controller.events = [];
  controller.pending = [];
  controller.startedAt = null;
  controller.lastLength = 0;
  controller.keystrokes = 0;
  controller.mistakes = 0;
  controller.submitted = false;
  controller.tickTimer = null;
  controller.inputTarget = { value: "", classList: { toggle() {} } };
  controller.promptTarget = { querySelectorAll: () => [] };
  controller.progressBarTarget = { style: {} };
  controller.accuracyTarget = { textContent: "", classList: { toggle() {} } };
  controller.rhythmTarget = { textContent: "" };
  controller.timeTarget = { textContent: "" };
  controller.hasSubmitTarget = false;
  controller.minSamplesValue = Number.MAX_SAFE_INTEGER;

  return controller;
}

async function loadController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/typing_fingerprint_controller.js", import.meta.url),
    "utf8"
  );
  const runnableSource = source
    .replace('import { Controller } from "@hotwired/stimulus";\n\n', "")
    .replace("export default class extends Controller", "return class TypingFingerprintController extends Controller");

  return new Function("Controller", runnableSource)(class {});
}
