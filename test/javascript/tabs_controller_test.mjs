import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

async function load() {
  const src = await readFile(new URL("../../app/javascript/controllers/tabs_controller.js", import.meta.url), "utf8");
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus";\n', "")
    .replace("export default class extends Controller", "return class C extends Controller");
  return new Function("Controller", body)(class {});
}

// Turbo ignores Back to a history entry whose state lost its `turbo` key, so the
// URL changes but the page stays. Tab switches must keep that state and not push.
test("tab switches keep Turbo's history state and never push entries", async () => {
  const calls = [];
  const turboState = { turbo: { restorationIdentifier: "r1", restorationIndex: 3 } };
  globalThis.window = { location: { hash: "" } };
  globalThis.history = {
    state: turboState,
    replaceState: (state, _t, url) => calls.push(["replace", state, url]),
    pushState: (state, _t, url) => calls.push(["push", state, url]),
  };
  const panel = (name) => ({ dataset: { tabPanel: name }, classList: { add() {}, remove() {} }, dispatchEvent() {} });
  const tab = (name) => ({ dataset: { tabName: name }, classList: { add() {}, remove() {} } });
  const C = await load();
  const c = new C();
  Object.assign(c, { defaultTabValue: "a", panelTargets: [panel("a"), panel("b")], tabTargets: [tab("a"), tab("b")] });

  c.connect();
  c.switch({ preventDefault() {}, currentTarget: { dataset: { tabName: "b" } } });

  assert.deepEqual(calls, [["replace", turboState, "#a"], ["replace", turboState, "#b"]]);
});
