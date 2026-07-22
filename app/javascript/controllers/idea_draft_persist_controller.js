import { Controller } from "@hotwired/stimulus";
import {
  collectDraftFields,
  decryptDraft,
  encryptDraft,
  hasMeaningfulDraft,
  restoreDraftFields,
  shouldShowResumePrompt,
} from "../lib/idea_draft_store.mjs";

export default class extends Controller {
  static targets = ["prompt", "savedAt", "error", "idleMessage", "storedMessage", "storedActions"];
  static values = {
    enabled: { type: Boolean, default: false },
    storageKey: String,
    unlockSeed: String,
    clearOnConnect: { type: Boolean, default: false },
    promptWithExistingContent: { type: Boolean, default: false },
    promptDelay: { type: Number, default: 6000 },
  };

  connect() {
    this.saveTimer = null;
    this.promptTimer = null;
    this.submittingAfterSave = false;

    if (this.clearOnConnectValue) {
      this.clearStoredDraft();
      return;
    }

    if (!this.enabledValue) return;
    this.queueResumePrompt();
    this.boundBeforeUnload = () => this.saveImmediately();
    window.addEventListener("beforeunload", this.boundBeforeUnload);
  }

  disconnect() {
    clearTimeout(this.saveTimer);
    clearTimeout(this.promptTimer);
    if (this.boundBeforeUnload) window.removeEventListener("beforeunload", this.boundBeforeUnload);
  }

  queueSave() {
    if (!this.enabledValue || this.submittingAfterSave) return;
    this.hidePrompt();
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveDraft(), 350);
    this.queueResumePrompt();
  }

  async submit(event) {
    if (!this.enabledValue || this.submittingAfterSave) return;

    event.preventDefault();
    clearTimeout(this.saveTimer);
    await this.saveDraft();
    this.submittingAfterSave = true;

    if (event.submitter && this.element.requestSubmit) {
      this.element.requestSubmit(event.submitter);
    } else {
      this.element.submit();
    }
  }

  async restore() {
    const record = this.readStoredRecord();
    if (!record) return;

    try {
      const draft = await decryptDraft(record, this.cryptoOptions());
      restoreDraftFields(this.element, draft);
      this.hidePrompt();
    } catch (_error) {
      this.showError("This saved idea draft cannot be unlocked in the current app session.");
    }
  }

  async discard() {
    const confirmed = await window.AppDialog?.confirm("Discard the saved idea draft on this device? This cannot be undone.", {
      title: "Discard saved draft?",
      confirmLabel: "Discard draft",
      variant: "danger",
    });
    if (!confirmed) return;
    this.clearStoredDraft();
    this.hidePrompt();
  }

  dismiss() {
    this.hidePrompt();
  }

  queueResumePrompt() {
    clearTimeout(this.promptTimer);
    this.promptTimer = setTimeout(() => this.showResumePromptIfNeeded(), this.promptDelayValue);
  }

  async showResumePromptIfNeeded() {
    const record = this.readStoredRecord();
    const currentDraft = collectDraftFields(this.element);
    if (!shouldShowResumePrompt({
      record,
      currentDraft,
      promptWithExistingContent: this.promptWithExistingContentValue,
    })) return;

    this.toggleStoredDraftMode(Boolean(record));

    if (record && this.hasSavedAtTarget) {
      this.savedAtTarget.textContent = record.savedAt ? new Date(record.savedAt).toLocaleString() : "recently";
    }
    if (this.hasPromptTarget) this.promptTarget.hidden = false;
  }

  toggleStoredDraftMode(hasStoredDraft) {
    if (this.hasIdleMessageTarget) this.idleMessageTarget.hidden = hasStoredDraft;
    if (this.hasStoredMessageTarget) this.storedMessageTarget.hidden = !hasStoredDraft;
    if (this.hasStoredActionsTarget) this.storedActionsTarget.hidden = !hasStoredDraft;
  }

  async saveDraft() {
    const draft = collectDraftFields(this.element);
    if (!hasMeaningfulDraft(draft)) {
      this.clearStoredDraft();
      return;
    }

    try {
      const record = await encryptDraft(draft, this.cryptoOptions());
      if (record) localStorage.setItem(this.storageKeyValue, JSON.stringify(record));
    } catch (_error) {
      this.showError("This browser could not protect the idea draft locally. Keep this page open until the idea is saved.");
    }
  }

  saveImmediately() {
    if (!this.enabledValue) return;
    // Fire and forget. The submit path awaits this; beforeunload is best-effort.
    this.saveDraft();
  }

  readStoredRecord() {
    try {
      const raw = localStorage.getItem(this.storageKeyValue);
      return raw ? JSON.parse(raw) : null;
    } catch (_error) {
      return null;
    }
  }

  clearStoredDraft() {
    localStorage.removeItem(this.storageKeyValue);
  }

  hidePrompt() {
    if (this.hasPromptTarget) this.promptTarget.hidden = true;
    if (this.hasErrorTarget) this.errorTarget.textContent = "";
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message;
      return;
    }
    window.AppDialog?.alert(message, { title: "Draft couldn’t be protected", confirmLabel: "Got it" });
  }

  cryptoOptions() {
    return {
      storageKey: this.storageKeyValue,
      unlockSeed: this.unlockSeedValue,
    };
  }
}
