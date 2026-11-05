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

const PENDING = '<article><div class="ask-agent-message--pending">Waiting</div></article>';
const ANSWERED = "<article>Done</article>";

// Controller wired to a fake messages box, fake timers and a scripted fetch; no DOM needed.
async function pollHarness({ html, responses }) {
  const AskAgentController = await loadAskAgentController();
  const controller = new AskAgentController();
  const timers = [];
  const box = {
    innerHTML: html, scrollTop: 0, scrollHeight: 1000, clientHeight: 400, replaced: 0,
    querySelector: (selector) => (selector.includes("pending") && box.innerHTML.includes("ask-agent-message--pending") ? {} : null),
    replaceChildren(...nodes) { box.replaced += 1; box.innerHTML = nodes[0]; },
  };
  const calls = [];
  const previous = { window: globalThis.window, document: globalThis.document, fetch: globalThis.fetch, FormData: globalThis.FormData };
  globalThis.FormData = class {};
  globalThis.window = {
    removeEventListener() {},
    setTimeout: (fn, ms) => timers.push({ fn, ms }) && timers.length,
    clearTimeout: (id) => { if (id) timers[id - 1] = { cleared: true }; },
  };
  globalThis.document = {
    visibilityState: "visible",
    removeEventListener() {},
    querySelector: () => null,
    getSelection: () => ({ isCollapsed: true }),
    getElementById: () => null,
    createElement: () => ({ set innerHTML(v) { this._h = v; this.childNodes = [v]; }, get innerHTML() { return this._h; } }),
  };
  globalThis.fetch = async (url) => { calls.push(url); return responses.shift(); };
  box.contains = () => true;
  const launcher = { dataset: {}, labels: [], setAttribute(k, v) { launcher.labels.push(v); } };
  const status = { textContent: "" };
  Object.assign(controller, { hasLauncherTarget: true, launcherTarget: launcher, hasStatusTarget: true, statusTarget: status, hasPanelTarget: true, panelTarget: { hidden: true } });
  Object.assign(controller, { hasMessagesTarget: true, messagesTarget: box, questionsUrlValue: "/q", element: { hidden: false }, seq: 0 });
  const restore = () => Object.assign(globalThis, previous);
  const live = () => timers.filter((t) => t.fn);
  return { controller, box, calls, timers, live, restore, launcher, status };
}

const ok = (body) => ({ ok: true, status: 200, redirected: false, text: async () => body });

test("ask agent polls every 3s only while a question is pending and stops once answered", async () => {
  const h = await pollHarness({ html: PENDING, responses: [ok(PENDING), ok(ANSWERED)] });
  try {
    h.controller.schedule();
    assert.equal(h.live().length, 1);
    assert.equal(h.live()[0].ms, 3000);

    await h.live()[0].fn(); // poll 1: still pending -> next poll queued
    assert.equal(h.live().length, 1);

    await h.live()[0].fn(); // poll 2: answered -> markup swapped, polling stops
    assert.equal(h.box.innerHTML, ANSWERED);
    assert.equal(h.live().length, 0);
    assert.equal(h.calls.length, 2);
  } finally {
    h.restore();
  }
});

test("ask agent does not poll when nothing is pending or the tab is hidden", async () => {
  const h = await pollHarness({ html: ANSWERED, responses: [] });
  try {
    h.controller.schedule();
    assert.equal(h.live().length, 0);
    h.box.innerHTML = PENDING;
    globalThis.document.visibilityState = "hidden";
    h.controller.schedule();
    assert.equal(h.live().length, 0);
  } finally {
    h.restore();
  }
});

test("ask agent never injects a redirected, 401 or 403 response and stops polling", async () => {
  for (const response of [
    { ok: true, status: 200, redirected: true, text: async () => "<html>lock page</html>" },
    { ok: false, status: 401, redirected: false, text: async () => "no" },
    { ok: false, status: 403, redirected: false, text: async () => "no" },
  ]) {
    const h = await pollHarness({ html: PENDING, responses: [response] });
    try {
      await h.controller.refresh();
      assert.equal(h.box.innerHTML, PENDING);
      assert.equal(h.box.replaced, 0);
      assert.equal(h.live().length, 0, "polling must stop");
    } finally {
      h.restore();
    }
  }
});

test("ask agent keeps the markup and retries when the network fails or the response is not ok", async () => {
  const h = await pollHarness({ html: PENDING, responses: [{ ok: false, status: 500, redirected: false, text: async () => "boom" }] });
  try {
    await h.controller.refresh();
    assert.equal(h.box.innerHTML, PENDING);
    assert.equal(h.live().length, 1, "retries");
    globalThis.fetch = async () => { throw new TypeError("offline"); };
    await h.controller.refresh();
    assert.equal(h.box.innerHTML, PENDING);
    assert.equal(h.live().length, 1, "retries after a network failure");
  } finally {
    h.restore();
  }
});

test("ask agent leaves the DOM alone when the markup is unchanged and when locked", async () => {
  const h = await pollHarness({ html: PENDING, responses: [ok(PENDING), ok(ANSWERED)] });
  try {
    await h.controller.refresh();
    assert.equal(h.box.replaced, 0);

    globalThis.document.getElementById = () => ({}); // typing-lock cover is up
    await h.controller.refresh();
    assert.equal(h.box.replaced, 0);
    assert.equal(h.calls.length, 1, "no request at all while locked");
  } finally {
    h.restore();
  }
});

test("ask agent backs off to 30s after 2 minutes without change and resets on a change", async () => {
  const h = await pollHarness({ html: PENDING, responses: [ok(PENDING + PENDING)] });
  try {
    h.controller.markChange();
    h.controller.changedAt = Date.now() - 130000;
    h.controller.schedule();
    assert.equal(h.live()[0].ms, 30000);
    await h.live()[0].fn(); // pending count 1 -> 2: a change, back to 3s
    assert.equal(h.live()[0].ms, 3000);
    h.controller.changedAt = Date.now() - 130000;
    h.controller.markChange();
    h.controller.schedule();
    assert.equal(h.live()[0].ms, 3000, "send/queued reset the clock");
  } finally {
    h.restore();
  }
});

test("ask agent marks the launcher unread and announces when an answer lands while closed, never opening the panel", async () => {
  const h = await pollHarness({ html: PENDING, responses: [ok(ANSWERED)] });
  try {
    h.controller.markChange();
    await h.controller.refresh();
    assert.equal("unread" in h.launcher.dataset, true);
    assert.match(h.launcher.labels.at(-1), /new answer/);
    assert.match(h.status.textContent, /new answer/);
    assert.equal(h.controller.panelTarget.hidden, true);
    h.controller.clearUnread();
    assert.equal("unread" in h.launcher.dataset, false);
  } finally {
    h.restore();
  }
});

test("ask agent skips the swap under a selection and retries, and ignores time-label-only changes", async () => {
  const withTime = (label) => `<article><time>${label}</time><div class="ask-agent-message--pending">Waiting</div></article>`;
  const h = await pollHarness({ html: withTime("1 minute ago"), responses: [ok(withTime("2 minutes ago")), ok(ANSWERED), ok(ANSWERED)] });
  try {
    h.controller.markChange();
    await h.controller.refresh();
    assert.equal(h.box.replaced, 0, "time-only difference");

    globalThis.document.getSelection = () => ({ isCollapsed: false, anchorNode: {} });
    await h.controller.refresh();
    assert.equal(h.box.replaced, 0, "selection inside the box");
    assert.equal(h.controller.deferred, true);

    globalThis.document.getSelection = () => ({ isCollapsed: true });
    await h.controller.refresh();
    assert.equal(h.box.innerHTML, ANSWERED);
    assert.equal(h.controller.deferred, false);
  } finally {
    h.restore();
  }
});

test("ask agent deferred swap keeps polling even when nothing is pending", async () => {
  const h = await pollHarness({ html: ANSWERED, responses: [] });
  try {
    h.controller.schedule();
    assert.equal(h.live().length, 0);
    h.controller.deferred = true;
    h.controller.schedule();
    assert.equal(h.live().length, 1);
  } finally {
    h.restore();
  }
});

test("ask agent in-flight refresh does not reschedule after disconnect", async () => {
  const h = await pollHarness({ html: PENDING, responses: [] });
  try {
    let release;
    globalThis.fetch = () => new Promise((resolve) => { release = () => resolve(ok(PENDING)); });
    const inflight = h.controller.refresh();
    h.controller.disconnect();
    release();
    await inflight;
    assert.equal(h.live().length, 0);
    const calls = h.calls.length;
    await h.controller.refresh();
    h.controller.schedule();
    assert.equal(h.live().length, 0);
    assert.equal(h.calls.length, calls);
  } finally {
    h.restore();
  }
});

function sendHarness(h) {
  const button = { disabled: false };
  const form = { action: "/q", querySelector: () => button };
  const body = { value: "What?", focused: false, focus() { body.focused = true; } };
  const error = { textContent: "", hidden: true };
  Object.assign(h.controller, { hasBodyTarget: true, bodyTarget: body, hasErrorTarget: true, errorTarget: error });
  return { button, body, error, event: { preventDefault() {}, currentTarget: form } };
}

test("ask agent send posts by fetch, guards double submit, clears and refocuses on success", async () => {
  const h = await pollHarness({ html: ANSWERED, responses: [] });
  try {
    const s = sendHarness(h);
    const requests = [];
    globalThis.fetch = async (url, options) => {
      requests.push({ url, options });
      return options?.method === "POST" ? { ok: true, status: 200, redirected: false, json: async () => ({ ok: true }) } : ok(PENDING);
    };
    const first = h.controller.send(s.event);
    assert.equal(s.button.disabled, true);
    await h.controller.send(s.event); // double click while in flight
    await first;
    assert.equal(requests.filter((r) => r.options?.method === "POST").length, 1);
    assert.equal(s.body.value, "");
    assert.equal(s.body.focused, true);
    assert.equal(s.button.disabled, false);
    assert.equal(h.box.innerHTML, PENDING, "new thread fetched without a page load");
  } finally {
    h.restore();
  }
});

test("ask agent send keeps the typed text and shows the error on failure", async () => {
  const h = await pollHarness({ html: ANSWERED, responses: [] });
  try {
    const s = sendHarness(h);
    globalThis.fetch = async () => ({ ok: false, status: 422, redirected: false, json: async () => ({ error: "disabled" }) });
    await h.controller.send(s.event);
    assert.equal(s.body.value, "What?");
    assert.equal(s.error.hidden, false);
    assert.match(s.error.textContent, /turned off/);
    assert.equal(s.button.disabled, false);

    globalThis.fetch = async () => { throw new TypeError("offline"); };
    await h.controller.send(s.event);
    assert.equal(s.body.value, "What?");
    assert.match(s.error.textContent, /Could not reach/);
  } finally {
    h.restore();
  }
});

test("ask agent queued opens without focus and refetches", async () => {
  const h = await pollHarness({ html: ANSWERED, responses: [ok(PENDING)] });
  try {
    const opened = [];
    h.controller.open = (event, options) => opened.push(options);
    await h.controller.queued();
    assert.deepEqual(opened, [{ focus: false }]);
    assert.equal(h.box.innerHTML, PENDING);
  } finally {
    h.restore();
  }
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
