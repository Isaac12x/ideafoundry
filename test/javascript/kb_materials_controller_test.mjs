import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

async function load() {
  const src = await readFile(new URL("../../app/javascript/controllers/kb_materials_controller.js", import.meta.url), "utf8");
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", "return class M extends Controller");
  return new Function("Controller", body)(class {});
}

const item = (stage, search) => ({ dataset: { stage, search }, hidden: false });
const chip = (filter) => ({ dataset: { filter }, classList: { toggle(c, on) { this.on = on } }, setAttribute(k, v) { this.pressed = v } });

async function setup(items, store = new Map()) {
  globalThis.sessionStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  const C = await load();
  const c = new C();
  const count = { textContent: "" };
  const group = { hidden: false, querySelectorAll: () => items, querySelector: () => count };
  Object.assign(c, {
    keyValue: "p", chipTargets: [chip("all"), chip("Frame"), chip("__none__")], itemTargets: items,
    groupTargets: [group], hasQueryTarget: true, queryTarget: { value: "" }, hasNoneTarget: true, noneTarget: { hidden: true },
  });
  return { c, count, group, store };
}

test("stage filter, no-stage filter and text query", async () => {
  const items = [item("Frame", "a.pdf"), item("", "b notes"), item("Test", "c")];
  const { c, count, group } = await setup(items);
  c.connect();
  assert.deepEqual(items.map((i) => i.hidden), [false, false, false]);
  c.pick({ currentTarget: { dataset: { filter: "Frame" } } });
  assert.deepEqual(items.map((i) => i.hidden), [false, true, true]);
  assert.equal(count.textContent, "1/3");
  c.pick({ currentTarget: { dataset: { filter: "__none__" } } });
  assert.deepEqual(items.map((i) => i.hidden), [true, false, true]);
  c.queryTarget.value = "zzz";
  c.apply();
  assert.equal(group.hidden, true);
  assert.equal(c.noneTarget.hidden, false);
});

test("filter persists per project and survives broken storage", async () => {
  const { c, store } = await setup([item("Frame", "x")]);
  c.connect();
  c.pick({ currentTarget: { dataset: { filter: "Frame" } } });
  assert.equal(store.get("kbp-filter:p"), "Frame");
  const again = await setup([item("Frame", "x")], store);
  again.c.connect();
  assert.equal(again.c.filter, "Frame");
  globalThis.sessionStorage = { getItem() { throw new Error("x") }, setItem() { throw new Error("x") } };
  assert.doesNotThrow(() => c.pick({ currentTarget: { dataset: { filter: "all" } } }));
});
