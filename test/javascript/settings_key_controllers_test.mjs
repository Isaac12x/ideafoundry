import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

async function load(file, name) {
  const src = await readFile(new URL(`../../app/javascript/controllers/${file}`, import.meta.url), "utf8");
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", `return class ${name} extends Controller`);
  return new Function("Controller", body)(class {});
}

test("settings index ignores modified clicks", async () => {
  const C = await load("settings_index_controller.js", "S");
  const store = new Map();
  const mk = () => ({ getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)) });
  globalThis.sessionStorage = mk();
  globalThis.localStorage = mk();
  globalThis.window = { scrollY: 5, scrollTo() {}, addEventListener() {}, removeEventListener() {} };
  globalThis.document = { addEventListener() {}, removeEventListener() {} };
  globalThis.location = { href: "http://x/settings" };
  const row = { href: "/settings/capture" };
  const c = new C();
  c.element = {
    contains: () => true, addEventListener(_, fn) { c.fn = fn }, removeEventListener() {},
    querySelectorAll: () => [],
  };
  c.markLast = () => {};
  c.connect();
  const ev = (extra) => ({ button: 0, target: { closest: () => row }, ...extra });
  for (const extra of [{ metaKey: true }, { ctrlKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }]) {
    c.fn(ev(extra));
  }
  assert.equal(store.size, 0);
  c.fn(ev({}));
  assert.equal(store.get("settings-index:last"), "/settings/capture");
});

test("key reveal ignores toggles while a fetch is pending", async () => {
  const C = await load("key_reveal_controller.js", "K");
  const c = new C();
  let calls = 0, release;
  c._toggle = () => { calls++; return new Promise((r) => { release = r }) };
  const first = c.toggle();
  await c.toggle();
  assert.equal(calls, 1);
  release();
  await first;
  const second = c.toggle();
  assert.equal(calls, 2);
  release();
  await second;
});
