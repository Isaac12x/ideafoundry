import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

// Minimal DOM fake: just what the controller touches.
class El {
  constructor(tag = "div") {
    this.tag = tag; this.children = []; this.attrs = {}; this.listeners = {}; this.dataset = {};
    this.cls = new Set(); this.style = {}; this.hidden = false; this.className = ""; this.parent = null;
    this.classList = {
      add: (c) => this.cls.add(c), remove: (c) => this.cls.delete(c),
      toggle: (c, on) => (on ? this.cls.add(c) : this.cls.delete(c)),
      contains: (c) => this.cls.has(c),
    };
  }
  setAttribute(k, v) { this.attrs[k] = String(v) }
  getAttribute(k) { return this.attrs[k] ?? null }
  removeAttribute(k) { delete this.attrs[k] }
  addEventListener(t, f) { (this.listeners[t] ||= []).push(f) }
  removeEventListener(t, f) { this.listeners[t] = (this.listeners[t] || []).filter((x) => x !== f) }
  append(...n) { n.forEach((c) => { c.parent = this; this.children.push(c) }) }
  replaceChildren() { this.children = [] }
  after(n) { n.parent = this.parent; this.parent.children.push(n) }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((c) => c !== this); this.parent = null }
  contains(n) { return n === this || this.children.some((c) => c.contains(n)) }
  focus() { globalThis.document.active = this }
  getBoundingClientRect() { return { left: 20, top: 100, bottom: 120, width: 80, height: 20 } }
  get offsetHeight() { return 150 }
  get offsetWidth() { return 120 }
  fire(t, ev = {}) { (this.listeners[t] || []).forEach((f) => f(ev)) }
  set textContent(v) { this._t = v }
  get textContent() { return this._t ?? "" }
  dispatchEvent(ev) { this.fire(ev.type, ev); return true }
}

function opt(value, text, extra = {}) {
  const o = new El("option"); o.value = value; o.textContent = text; Object.assign(o, extra); return o;
}

async function setup({ options, selected = 0, disabled = false, innerHeight = 800 } = {}) {
  const body = new El("body");
  const winL = {}, docL = {};
  globalThis.document = {
    body, active: null,
    createElement: (t) => new El(t),
    addEventListener: (t, f) => (docL[t] ||= []).push(f),
    removeEventListener: (t, f) => (docL[t] = (docL[t] || []).filter((x) => x !== f)),
  };
  globalThis.window = {
    innerHeight, innerWidth: 1000,
    addEventListener: (t, f) => (winL[t] ||= []).push(f),
    removeEventListener: (t, f) => (winL[t] = (winL[t] || []).filter((x) => x !== f)),
  };
  globalThis.Event = class { constructor(type, init = {}) { this.type = type; Object.assign(this, init) } };
  const src = await readFile(new URL("../../app/javascript/controllers/select_menu_controller.js", import.meta.url), "utf8");
  const code = src
    .replace('import { Controller } from "@hotwired/stimulus"\n', "")
    .replace("export default class extends Controller", "return class C extends Controller");
  const C = new Function("Controller", code)(class {});
  const select = new El("select");
  select.className = "kbp-tag";
  select.options = options || [opt("a", "Alpha", { dataset: { tone: "success" } }), opt("b", "Beta"), opt("c", "Gamma")];
  select.selectedIndex = selected;
  select.disabled = disabled;
  select.value = select.options[selected]?.value;
  select.tabIndex = 0;
  Object.defineProperty(select, "value", {
    get() { return this.options[this.selectedIndex]?.value },
    set(v) { this.selectedIndex = this.options.findIndex((o) => o.value === v) },
  });
  body.append(select);
  const changes = [];
  select.addEventListener("change", (e) => changes.push(e));
  const c = new C();
  c.element = select;
  c.connect();
  const key = (k, extra = {}) => c.trigger.fire("keydown", { key: k, preventDefault() {}, stopPropagation() {}, ...extra });
  return { c, select, body, changes, key, docL, winL };
}

test("connect inserts trigger (copying class) and hidden popover, hides select", async () => {
  const { c, select, body } = await setup();
  assert.equal(c.trigger.className, "kbp-tag select-menu-trigger");
  assert.equal(c.trigger.getAttribute("aria-haspopup"), "listbox");
  assert.equal(c.trigger.getAttribute("aria-expanded"), "false");
  assert.equal(c.labelEl.textContent, "Alpha");
  assert.equal(c.trigger.dataset.tone, "success");
  assert.equal(c.popover.hidden, true);
  assert.equal(c.popover.getAttribute("role"), "listbox");
  assert.ok(select.classList.contains("select-menu-native"));
  assert.ok(body.children.includes(c.trigger) && body.children.includes(c.popover));
  c.connect(); // reconnect must not duplicate
  assert.equal(body.children.length, 3);
});

test("open builds options with aria-selected, closes on Esc", async () => {
  const { c, key } = await setup({ selected: 1 });
  key("Enter");
  assert.equal(c.popover.hidden, false);
  assert.equal(c.trigger.getAttribute("aria-expanded"), "true");
  assert.deepEqual(c.items.map((i) => i.getAttribute("aria-selected")), ["false", "true", "false"]);
  assert.equal(c.trigger.getAttribute("aria-activedescendant"), c.items[1].id);
  assert.equal(c.popover.dataset.placement, "bottom");
  key("Escape");
  assert.equal(c.popover.hidden, true);
  assert.equal(globalThis.document.active, c.trigger);
});

test("arrows, Home/End skip disabled; Enter selects and fires bubbling change", async () => {
  const { c, select, changes, key } = await setup({
    options: [opt("a", "Alpha"), opt("b", "Beta", { disabled: true }), opt("c", "Gamma"), opt("d", "Delta")],
  });
  key("ArrowDown");
  key("ArrowDown");
  assert.equal(c.active, 2);
  key("End");
  assert.equal(c.active, 3);
  key("ArrowDown");
  assert.equal(c.active, 3);
  key("Home");
  assert.equal(c.active, 0);
  key("ArrowDown");
  key("Enter");
  assert.equal(select.value, "c");
  assert.equal(changes.length, 1);
  assert.equal(changes[0].bubbles, true);
  assert.equal(c.labelEl.textContent, "Gamma");
  assert.equal(c.popover.hidden, true);
  assert.equal(globalThis.document.active, c.trigger);
});

test("choosing the already-selected option just closes", async () => {
  const { c, changes, key } = await setup();
  key("ArrowDown");
  key("Enter");
  assert.equal(changes.length, 0);
  assert.equal(c.popover.hidden, true);
});

test("type-ahead jumps to matching option; Tab closes", async () => {
  const { c, key } = await setup();
  key("ArrowDown");
  key("g");
  assert.equal(c.active, 2);
  key("Tab");
  assert.equal(c.popover.hidden, true);
});

test("outside pointerdown, scroll and resize close; popover scroll does not", async () => {
  const { c, key, docL, winL } = await setup();
  key("ArrowDown");
  docL.pointerdown[0]({ target: c.items[0] });
  assert.equal(c.popover.hidden, false);
  docL.pointerdown[0]({ target: new El() });
  assert.equal(c.popover.hidden, true);
  key("ArrowDown");
  winL.scroll[0]({ target: c.popover });
  assert.equal(c.popover.hidden, false);
  winL.scroll[0]({ target: new El() });
  assert.equal(c.popover.hidden, true);
  key("ArrowDown");
  winL.resize[0]();
  assert.equal(c.popover.hidden, true);
});

test("flips upward when not enough room below", async () => {
  const { c, key } = await setup({ innerHeight: 200 });
  key("ArrowDown");
  assert.equal(c.popover.dataset.placement, "top");
  assert.equal(c.popover.style.top, "8px"); // 100 - 4 - 150 clamped to 8
});

test("disabled select does not open", async () => {
  const { c, key } = await setup({ disabled: true });
  assert.equal(c.trigger.disabled, true);
  key("Enter");
  assert.equal(c.popover.hidden, true);
});

test("disconnect removes nodes and listeners, unhides select", async () => {
  const { c, select, body, docL, winL, key } = await setup();
  key("ArrowDown");
  c.disconnect();
  assert.deepEqual(body.children, [select]);
  assert.ok(!select.classList.contains("select-menu-native"));
  assert.equal(docL.pointerdown.length, 0);
  assert.equal(winL.scroll.length, 0);
  c.connect();
  assert.equal(body.children.length, 3);
});
