import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "form",
    "input",
    "payload",
    "prompt",
    "submit",
    "progressBar",
    "accuracy",
    "time",
    "rhythm",
    "lastKey",
    "key",
    "decoy"
  ];

  static values = {
    mode: String,
    text: String,
    minSamples: Number,
    result: String,
    redirectUrl: String
  };

  connect() {
    this.events = [];
    this.pending = [];
    this.startedAt = null;
    this.lastLength = 0;
    this.submitted = false;
    this.transitionComplete = false;
    this.redirectFallbackTimer = null;
    this.scheduleRedirectFallback();
    if (!this.hasInputTarget) return;

    this.renderPrompt();
    this.updateDisplay();
    if (this.resultValue !== "matched") this.inputTarget.focus();
  }

  disconnect() {
    if (this.redirectFallbackTimer) clearTimeout(this.redirectFallbackTimer);
  }

  keydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;

    this.startedAt ||= performance.now();
    this.activateKey(event.key);

    if (event.key.length !== 1) return;

    const index = this.inputTarget.value.length;
    this.pending.push({
      key: event.key,
      index,
      down: performance.now()
    });
  }

  keyup(event) {
    const pending = [...this.pending].reverse().find((item) => item.key === event.key && item.up === undefined);
    if (pending) {
      pending.up = performance.now();
      this.events.push(pending);
    }

    this.deactivateKey(event.key);
    this.lastKeyTarget.textContent = event.key === " " ? "Space" : event.key;
    this.updateDisplay();
  }

  input() {
    const value = this.inputTarget.value;
    if (value.length < this.lastLength) {
      this.events = this.events.filter((event) => event.index < value.length);
      this.pending = this.pending.filter((event) => event.index < value.length);
    }

    this.lastLength = value.length;
    this.updateDisplay();
  }

  paste(event) {
    event.preventDefault();
  }

  submit(event) {
    if (!this.isComplete()) {
      event.preventDefault();
      return;
    }

    this.payloadTarget.value = JSON.stringify(this.validEvents());
    if (this.modeValue === "unlock") {
      event.preventDefault();
      this.submitUnlock();
      return;
    }

    this.submitted = true;
  }

  renderPrompt() {
    this.promptTarget.replaceChildren(
      ...this.textValue.split("").map((char, index) => {
        const span = document.createElement("span");
        span.dataset.index = index;
        span.textContent = char === " " ? "·" : char;
        if (char === " ") span.classList.add("is-space");
        return span;
      })
    );
  }

  updateDisplay() {
    const value = this.inputTarget.value;
    const validPrefix = this.validPrefixLength(value);
    const hasMismatch = validPrefix < value.length;

    this.promptTarget.querySelectorAll("span").forEach((span, index) => {
      span.classList.toggle("is-typed", index < validPrefix);
      span.classList.toggle("is-current", index === value.length && !hasMismatch);
      span.classList.toggle("is-error", hasMismatch && index >= validPrefix && index < value.length);
    });

    const progress = Math.min(100, (validPrefix / this.textValue.length) * 100);
    this.progressBarTarget.style.width = `${progress}%`;
    this.inputTarget.classList.toggle("has-error", hasMismatch);

    const accuracy = value.length === 0 ? 100 : Math.round((validPrefix / value.length) * 100);
    this.accuracyTarget.textContent = `${accuracy}%`;
    this.rhythmTarget.textContent = `${this.validEvents().length}`;
    this.updateTime();

    const complete = this.isComplete();
    if (this.hasSubmitTarget) this.submitTarget.disabled = !complete;
    if (complete) this.submitCompletedSample();
  }

  updateTime() {
    if (!this.startedAt) {
      this.timeTarget.textContent = "00:00";
      return;
    }

    const totalSeconds = Math.floor((performance.now() - this.startedAt) / 1000);
    const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0");
    const seconds = String(totalSeconds % 60).padStart(2, "0");
    this.timeTarget.textContent = `${minutes}:${seconds}`;
  }

  validPrefixLength(value) {
    let index = 0;
    while (index < value.length && value[index] === this.textValue[index]) index += 1;
    return index;
  }

  isComplete() {
    return this.inputTarget.value === this.textValue && this.validEvents().length >= this.minSamplesValue;
  }

  submitCompletedSample() {
    if (!["enroll", "unlock"].includes(this.modeValue) || this.submitted) return;
    if (this.pending.some((event) => event.up === undefined)) return;

    this.payloadTarget.value = JSON.stringify(this.validEvents());
    this.formTarget.requestSubmit();
  }

  scheduleRedirectFallback() {
    if (this.resultValue !== "matched" || !this.redirectUrlValue) return;

    this.redirectFallbackTimer = setTimeout(() => {
      this.completeUnlockTransition();
    }, 4000);
  }

  async completeUnlockTransition() {
    if (this.transitionComplete) return;

    this.transitionComplete = true;
    this.element.classList.add("typing-lock-shell--handoff");

    if (this.redirectFallbackTimer) {
      clearTimeout(this.redirectFallbackTimer);
      this.redirectFallbackTimer = null;
    }

    if (!this.redirectUrlValue) return;

    try {
      const response = await fetch(this.redirectUrlValue, {
        method: "GET",
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      });

      if (!response.ok) throw new Error(`Unlock redirect failed with ${response.status}`);

      const markup = await response.text();
      this.replaceWithResponse(markup, { url: this.redirectUrlValue });
    } catch (_error) {
      window.location.assign(this.redirectUrlValue);
    }
  }

  async submitUnlock() {
    if (this.submitted) return;

    this.submitted = true;
    this.hideDecoyScore();

    try {
      const response = await fetch(this.formTarget.action, {
        method: this.formTarget.method.toUpperCase(),
        body: new FormData(this.formTarget),
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      });
      const markup = await response.text();

      if (response.ok) {
        this.replaceWithResponse(markup);
        return;
      }

      this.showDecoyScore();
      this.submitted = false;
    } catch (_error) {
      this.formTarget.submit();
    }
  }

  showDecoyScore() {
    if (!this.hasDecoyTarget) return;

    this.decoyTarget.textContent = "This is your score";
    this.decoyTarget.hidden = false;
    this.decoyTarget.classList.add("is-visible");
  }

  hideDecoyScore() {
    if (!this.hasDecoyTarget) return;

    this.decoyTarget.hidden = true;
    this.decoyTarget.classList.remove("is-visible");
  }

  replaceWithResponse(markup, options = {}) {
    const nextDocument = new DOMParser().parseFromString(markup, "text/html");
    const nextHeader = nextDocument.querySelector(".app-header");
    const nextMain = nextDocument.querySelector(".app-main");
    const currentHeader = document.querySelector(".app-header");
    const currentMain = document.querySelector(".app-main");

    if (!nextMain || !currentMain) {
      document.open();
      document.write(markup);
      document.close();
      return;
    }

    document.title = nextDocument.title;
    this.syncBodyAttributes(nextDocument.body);
    if (nextHeader && currentHeader) currentHeader.replaceWith(nextHeader);
    currentMain.replaceWith(nextMain);

    if (options.url) {
      window.history.replaceState({}, nextDocument.title, options.url);
    }
  }

  syncBodyAttributes(nextBody) {
    [...document.body.attributes].forEach((attribute) => {
      if (!nextBody.hasAttribute(attribute.name)) {
        document.body.removeAttribute(attribute.name);
      }
    });

    [...nextBody.attributes].forEach((attribute) => {
      document.body.setAttribute(attribute.name, attribute.value);
    });
  }

  validEvents() {
    return this.events.filter((event) => (
      event.up &&
      event.index < this.textValue.length &&
      event.key === this.textValue[event.index]
    ));
  }

  activateKey(key) {
    this.keyTargets
      .filter((target) => target.dataset.key === key)
      .forEach((target) => target.classList.add("is-active"));
  }

  deactivateKey(key) {
    this.keyTargets
      .filter((target) => target.dataset.key === key)
      .forEach((target) => target.classList.remove("is-active"));
  }
}
