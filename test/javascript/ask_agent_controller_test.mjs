import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("ask agent invention icon reuses the stored daily choice", async () => {
  const AskAgentController = await loadAskAgentController();
  const controller = new AskAgentController();
  const restoreStorage = installLocalStorage();

  try {
    window.localStorage.setItem(
      AskAgentController.inventionStorageKey,
      JSON.stringify({ day: "2026-06-03", invention: "gyro" })
    );
    controller.currentInventionDay = () => "2026-06-03";

    assert.equal(controller.dailyInvention(), "gyro");
    assert.equal(controller.initialInventionIndex(), AskAgentController.inventionVariants.indexOf("gyro"));
  } finally {
    restoreStorage();
  }
});

test("ask agent invention icon stores at most one new choice per day", async () => {
  const AskAgentController = await loadAskAgentController();
  const controller = new AskAgentController();
  const restoreStorage = installLocalStorage();
  const previousInvention = controller.pickDailyInvention("2026-06-04");

  try {
    window.localStorage.setItem(
      AskAgentController.inventionStorageKey,
      JSON.stringify({ day: "2026-06-03", invention: previousInvention })
    );
    controller.currentInventionDay = () => "2026-06-04";

    const invention = controller.dailyInvention();
    const stored = JSON.parse(window.localStorage.getItem(AskAgentController.inventionStorageKey));

    assert.notEqual(invention, previousInvention);
    assert.equal(stored.day, "2026-06-04");
    assert.equal(stored.invention, invention);
    assert.equal(controller.dailyInvention(), invention);
  } finally {
    restoreStorage();
  }
});

test("ask agent invention refresh is scheduled for the next local day", async () => {
  const AskAgentController = await loadAskAgentController();
  const controller = new AskAgentController();
  const now = new Date(2026, 5, 3, 23, 45, 0);

  assert.equal(controller.millisecondsUntilNextInventionDay(now), 15 * 60 * 1000);
});

async function loadAskAgentController() {
  const source = await readFile(
    new URL("../../app/javascript/controllers/ask_agent_controller.js", import.meta.url),
    "utf8"
  );
  const runnableSource = source
    .replace('import { Controller } from "@hotwired/stimulus"\n\n', "")
    .replace("export default class extends Controller", "return class AskAgentController extends Controller");

  return new Function("Controller", runnableSource)(class {});
}

function installLocalStorage() {
  const previousWindow = globalThis.window;
  const store = new Map();

  globalThis.window = {
    localStorage: {
      getItem(key) {
        return store.has(key) ? store.get(key) : null;
      },
      setItem(key, value) {
        store.set(key, String(value));
      },
    },
  };

  return () => {
    globalThis.window = previousWindow;
  };
}
