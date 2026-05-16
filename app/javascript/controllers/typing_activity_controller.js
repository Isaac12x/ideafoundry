import { Controller } from "@hotwired/stimulus";

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
    document.addEventListener("keydown", this.boundHandleShortcut);
    this.scheduleLock();
  }

  disconnect() {
    if (this.timeoutTimer) clearTimeout(this.timeoutTimer);
    if (!this.boundRecordActivity) return;

    this.activityEvents.forEach(([target, eventName]) => {
      target.removeEventListener(eventName, this.boundRecordActivity);
    });
    document.removeEventListener("keydown", this.boundHandleShortcut);
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
    return !event.defaultPrevented &&
      !event.repeat &&
      event.code === "KeyL" &&
      event.shiftKey &&
      !event.altKey &&
      (event.ctrlKey || event.metaKey);
  }

  manualLock() {
    if (this.locked) return;

    this.locked = true;

    if (this.hasLockFormTarget) {
      if (typeof this.lockFormTarget.requestSubmit === "function") {
        this.lockFormTarget.requestSubmit();
      } else {
        this.lockFormTarget.submit();
      }
      return;
    }

    this.submitLockAction();
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

  lock() {
    if (this.locked) return;

    this.locked = true;
    this.submitLockAction();
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
