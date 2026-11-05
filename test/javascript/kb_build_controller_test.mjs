import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

async function load() {
  const src = await readFile(new URL("../../app/javascript/controllers/kb_build_controller.js", import.meta.url), "utf8");
  const body = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", "return class B extends Controller");
  return new Function("Controller", body)(class {});
}

const row = (id, v) => ({ dataset: { id }, querySelector: (sel) => ({ value: v[sel.match(/"(\w+)"/)[1]] }) });

test("sync serializes rows in DOM order plus a non-blank add field", async () => {
  const B = await load();
  const c = new B();
  const field = { value: "" };
  Object.assign(c, {
    fieldTarget: field,
    rowTargets: [row("a", { title: "Joinery", status: "known", note: "", links: "x.md" }), row("b", { title: "Roofing", status: "todo", note: "n", links: "" })],
    addTarget: { value: " Plumbing " },
  });
  globalThis.document = { activeElement: null };
  c.sync();
  const items = JSON.parse(field.value);
  assert.deepEqual(items.map((i) => i.title), ["Joinery", "Roofing", "Plumbing"]);
  assert.deepEqual(items[0], { id: "a", title: "Joinery", status: "known", note: "", links: "x.md" });
  assert.deepEqual(items[2], { title: "Plumbing", status: "todo" });
});
