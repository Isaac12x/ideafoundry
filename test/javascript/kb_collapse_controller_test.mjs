import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

async function load() {
  const src = await readFile(new URL("../../app/javascript/controllers/kb_collapse_controller.js", import.meta.url), "utf8");
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", "return class C extends Controller");
  return new Function("Controller", body)(class {});
}

async function setup({ open, key = "k", store = new Map() }) {
  globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  const C = await load();
  const c = new C();
  const classes = new Set();
  const body = { hidden: !open };
  const toggle = { attrs: {}, setAttribute(k, v) { this.attrs[k] = v } };
  Object.assign(c, {
    keyValue: key, openValue: open, hasBodyTarget: true, bodyTarget: body, hasToggleTarget: true, toggleTarget: toggle,
    element: { classList: { toggle: (n, on) => (on ? classes.add(n) : classes.delete(n)) } },
  });
  return { c, body, toggle, classes, store };
}

test("renders the server default, then a remembered choice wins on connect", async () => {
  const store = new Map([["k", "1"]]);
  const { c, body, toggle, classes } = await setup({ open: false, store });
  c.connect();
  assert.equal(c.openValue, true);
  assert.equal(body.hidden, false);
  assert.equal(toggle.attrs["aria-expanded"], "true");
  assert.ok(classes.has("is-open"));
});

test("toggle persists; show does not; storage failures are swallowed", async () => {
  const { c, store } = await setup({ open: true });
  c.connect();
  c.toggle();
  assert.equal(c.openValue, false);
  assert.equal(store.get("k"), "0");
  c.show();
  assert.equal(c.openValue, true);
  assert.equal(store.get("k"), "0");
  globalThis.localStorage = { getItem() { throw new Error("x") }, setItem() { throw new Error("x") } };
  assert.doesNotThrow(() => { c.connect(); c.toggle(); });
});
