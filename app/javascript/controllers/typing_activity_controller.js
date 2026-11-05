import { Controller } from "@hotwired/stimulus";
import { binding, matches } from "lib/shortcut_bindings";

const COVER_ID = "typing-lock-cover";
const LOCK_RETRY_DELAYS = [0, 250, 1000];
const LOCK_BACKOFF_MS = 2000; // offline: after the quick attempts, 2s, 4s, 8s, then every 15s (or at once on "online")
const LOCK_BACKOFF_MAX_MS = 15_000;
const DRAFT_WAIT_MS = 300; // drafts are debounced 250ms and stored encrypted locally; never hold the lock page up longer than this
const SCROLL_KEY = "typing-lock:scroll";
// Inner scroll panes that hold the reading position on some pages (the KB viewer and its sidebar tree).
const PANES = [".kb-document__body", ".kb-content-area", ".kb-sidebar-inner"];

export default class extends Controller {
  static targets = ["lockForm"];

  static values = {
    url: String,
    lockUrl: String,
    lockActionUrl: String,
    shortcut: String,
    timeoutSeconds: Number
  };

  connect() {
    if (!this.hasUrlValue || !this.timeoutSecondsValue) return;

    this.timeoutMs = this.timeoutSecondsValue * 1000;
    this.heartbeatIntervalMs = Math.min(Math.max(this.timeoutMs / 4, 15_000), 60_000);
    this.lastActivityAt = Date.now();
    this.lastHeartbeatAt = Date.now();
    this.heartbeatInFlight = false;
    this.locked = false;
    this.boundRecordActivity = this.recordActivity.bind(this);
    this.boundHandleShortcut = this.handleShortcut.bind(this);

    this.activityEvents.forEach(([target, eventName]) => {
      target.addEventListener(eventName, this.boundRecordActivity, { passive: true });
    });
    // Capture: an editor, player or input that stops keydown must not be able to swallow the lock shortcut.
    document.addEventListener("keydown", this.boundHandleShortcut, true);
    this.boundCheckDeadline = (event) => this.checkDeadline(event);
    window.addEventListener("pageshow", this.boundCheckDeadline);
    window.addEventListener("focus", this.boundCheckDeadline);
    // A Turbo body swap rebuilds this controller while the cover (on <html>) is still up: stay locked.
    if (document.getElementById(COVER_ID)) this.locked = true;
    this.scheduleLock();
    this.restoreScroll();
    this.replayEarlyKeys()
  }

  // Chords pressed while the page was still loading were buffered by an inline script in the layout head.
  replayEarlyKeys() {
    const early = window.__earlyKeys
    window.__earlyKeys = null
    if (early?.some((event) => this.isLockShortcut(event))) this.manualLock()
  }

  disconnect() {
    if (this.timeoutTimer) clearTimeout(this.timeoutTimer);
    if (!this.boundRecordActivity) return;

    this.activityEvents.forEach(([target, eventName]) => {
      target.removeEventListener(eventName, this.boundRecordActivity);
    });
    document.removeEventListener("keydown", this.boundHandleShortcut, true);
    window.removeEventListener("pageshow", this.boundCheckDeadline);
    window.removeEventListener("focus", this.boundCheckDeadline);
  }

  // Timers are throttled in background tabs and frozen in sleep; the wall clock is the truth.
  // Called on tab visible / pageshow / focus, ahead of paint, so an overdue tab is covered before it shows.
  checkDeadline(event) {
    if (this.locked) {
      // Restored from the back/forward cache while locked: the cover is still up, finish the lock.
      if (event?.persisted) this.navigateToLock();
      return;
    }
    if (Date.now() - this.lastActivityAt >= this.timeoutMs) this.lock();
  }

  recordActivity(event) {
    if (this.locked) return;
    if (event?.type === "visibilitychange" && document.visibilityState !== "visible") return;

    const now = Date.now();
    if (now - this.lastActivityAt >= this.timeoutMs) {
      this.lock();
      return;
    }

    this.lastActivityAt = now;
    this.scheduleLock();

    if (now - this.lastHeartbeatAt >= this.heartbeatIntervalMs) {
      this.sendActivity();
    }
  }

  scheduleLock() {
    if (this.timeoutTimer) clearTimeout(this.timeoutTimer);

    this.timeoutTimer = setTimeout(() => {
      this.lock();
    }, this.timeoutMs);
  }

  sendActivity() {
    if (this.heartbeatInFlight) return;

    this.lastHeartbeatAt = Date.now();
    this.heartbeatInFlight = true;

    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      }
    }).then((response) => {
      if (response.status === 401) this.lock();
    }).catch(() => {
      this.lastHeartbeatAt = 0;
    }).finally(() => {
      this.heartbeatInFlight = false;
    });
  }

  handleShortcut(event) {
    if (!this.isLockShortcut(event)) return;

    event.preventDefault();
    this.manualLock();
  }

  isLockShortcut(event) {
    return !event.defaultPrevented && !event.repeat && matches(binding("lock"), event);
  }

  manualLock() {
    this.lock();
  }

  // The lock button's form: same immediate path, never a plain submit.
  lockFormTargetConnected(form) {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      this.lock();
    });
  }

  // Waits (briefly) for unsaved textarea drafts to land and remembers the scroll position for after the unlock.
  async leave() {
    const detail = { wait: [] };
    document.dispatchEvent(new CustomEvent("draft:flush", { detail }));
    try {
      sessionStorage.setItem(SCROLL_KEY, JSON.stringify({ path: location.pathname + location.search, y: window.scrollY, panes: Object.fromEntries(PANES.map((sel) => [sel, document.querySelector(sel)?.scrollTop || 0])) }));
    } catch { /* private mode: unlock lands at the top */ }
    await Promise.race([Promise.allSettled(detail.wait), new Promise((resolve) => setTimeout(resolve, DRAFT_WAIT_MS))]);
  }

  restoreScroll() {
    try {
      const saved = JSON.parse(sessionStorage.getItem(SCROLL_KEY) || "null");
      sessionStorage.removeItem(SCROLL_KEY);
      if (saved?.path === location.pathname + location.search) requestAnimationFrame(() => {
        window.scrollTo(0, saved.y);
        Object.entries(saved.panes || {}).forEach(([sel, top]) => { const pane = document.querySelector(sel); if (pane && top) pane.scrollTop = top; });
      });
    } catch { /* nothing saved */ }
  }

  // Every trigger (shortcut, button, timeout, 401 heartbeat) lands here. Order matters:
  // 1. cover synchronously (same frame, nothing awaited), 2. flush drafts and lock the server session in parallel,
  // 3. navigate to the lock page. The cover never comes off: a failed request retries, then falls back to a form post.
  lock() {
    if (this.locked) return;

    this.locked = true;
    this.cover();
    const drafts = this.drafting = this.leave();
    this.requestServerLock().then(() => drafts).then(() => this.navigateToLock());
  }

  cover() {
    this.hideAskAgent();
    if (document.getElementById(COVER_ID)) return;

    document.querySelectorAll("video, audio").forEach((media) => media.pause());
    // Top-layer elements would paint above the cover.
    document.querySelectorAll("dialog[open]").forEach((dialog) => dialog.close());
    if (document.fullscreenElement) document.exitFullscreen?.().catch?.(() => {});
    if (document.pictureInPictureElement) document.exitPictureInPicture?.().catch?.(() => {});
    document.activeElement?.blur?.();

    const cover = document.createElement("div");
    cover.id = COVER_ID;
    cover.setAttribute("role", "alert");
    cover.setAttribute("aria-label", "Locking");
    cover.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#0b0b0f;cursor:wait;display:flex;align-items:flex-end;justify-content:center;padding-bottom:3rem";
    document.documentElement.appendChild(cover);
    if (document.body) document.body.inert = true;
    // Swallow every key (Tab, Enter, Escape) while locked; the cover itself swallows the pointer.
    window.addEventListener("keydown", (event) => { event.preventDefault(); event.stopImmediatePropagation(); }, true);
    // A Turbo visit already in flight must not swap a live page in under the cover or start another one.
    for (const type of ["turbo:before-visit", "turbo:before-render", "turbo:before-frame-render"]) document.addEventListener(type, (event) => event.preventDefault());
  }

  // Resolves once the server session is locked (the redirect itself is not followed: the lock page renders later).
  // After the quick attempts fail and the browser says it is online, a plain form post is tried too (it can work where fetch cannot). If we are still here,
  // the cover stays and keeps retrying with backoff (at once on "online"); offline it says so quietly. Never reveals.
  async requestServerLock() {
    if (!this.hasLockActionUrlValue) return;

    for (let attempt = 0; ; attempt++) {
      const quick = attempt < LOCK_RETRY_DELAYS.length;
      const delay = quick ? LOCK_RETRY_DELAYS[attempt] : Math.min((this.backoffBaseMs ?? LOCK_BACKOFF_MS) * 2 ** (attempt - LOCK_RETRY_DELAYS.length), LOCK_BACKOFF_MAX_MS);
      if (delay) await this.waitOnline(delay);
      let offline = false;
      try {
        const response = await fetch(this.lockActionUrlValue, {
          method: "POST",
          credentials: "same-origin",
          redirect: "manual",
          keepalive: true,
          headers: { "Accept": "text/html", "X-CSRF-Token": this.csrfToken() }
        });
        if (response.type === "opaqueredirect" || response.ok) return this.showOffline(false);
      } catch { offline = true; }
      // Offline a form post only swaps the cover for the browser's error page and leaves the server session unlocked: skip it.
      if (attempt === LOCK_RETRY_DELAYS.length - 1 && globalThis.navigator?.onLine !== false) { await this.drafting; this.submitLockAction(); }
      if (offline && attempt >= LOCK_RETRY_DELAYS.length - 1) this.showOffline(true);
    }
  }

  waitOnline(ms) {
    return new Promise((resolve) => {
      const done = () => { clearTimeout(timer); window.removeEventListener?.("online", done); resolve(); };
      const timer = setTimeout(done, ms);
      window.addEventListener("online", done);
    });
  }

  // A small quiet line on the cover; nothing from the workspace.
  showOffline(on) {
    const cover = document.getElementById(COVER_ID);
    if (!cover) return;

    cover.style.cursor = on ? "default" : "wait";
    cover.setAttribute("aria-label", on ? "Locked. Offline, retrying" : "Locking");
    let label = cover.firstChild;
    if (!on) return label?.remove?.();
    if (label) return;

    label = document.createElement("p");
    label.textContent = "Locked. Offline, retrying";
    label.style.cssText = "margin:0;font:500 13px/1.4 system-ui,-apple-system,sans-serif;color:#9a9aa6";
    cover.appendChild(label);
  }

  navigateToLock() {
    if (!this.hasLockActionUrlValue) {
      this.submitLockAction();
    } else {
      window.location.replace(this.lockUrlValue || "/");
    }
  }

  submitLockAction() {
    if (!this.hasLockActionUrlValue) {
      window.location.assign(this.lockUrlValue || "/");
      return;
    }

    const form = document.createElement("form");
    form.method = "post";
    form.action = this.lockActionUrlValue;

    const token = this.csrfToken();
    if (token) {
      const csrfInput = document.createElement("input");
      csrfInput.type = "hidden";
      csrfInput.name = "authenticity_token";
      csrfInput.value = token;
      form.appendChild(csrfInput);
    }

    document.body.appendChild(form);
    form.submit();
  }

  hideAskAgent() {
    const shell = document.getElementById("ask-agent");
    if (!shell) return;

    shell.hidden = true;
    shell.setAttribute("aria-hidden", "true");
    shell.querySelectorAll("[data-ask-agent-target='backdrop'], [data-ask-agent-target='panel']").forEach((element) => {
      element.hidden = true;
    });
    shell.querySelector("[data-ask-agent-target='launcher']")?.setAttribute("aria-expanded", "false");
    document.body.classList.remove("ask-agent-open");
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }

  get activityEvents() {
    return [
      [document, "keydown"],
      [document, "pointerdown"],
      [document, "pointermove"],
      [document, "touchstart"],
      [document, "visibilitychange"],
      [window, "scroll"]
    ];
  }
}
