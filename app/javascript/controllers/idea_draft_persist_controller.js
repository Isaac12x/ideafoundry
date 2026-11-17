import { Controller } from "@hotwired/stimulus";
import { confirmDialog, alertDialog } from "lib/app_dialog"
import {
  collectDraftFields,
  decryptDraft,
  encryptDraft,
  hasMeaningfulDraft,
  restoreDraftFields,
  shouldShowResumePrompt,
} from "lib/idea_draft_store";

export default class extends Controller {
  static targets = ["prompt", "savedAt", "error", "idleMessage", "storedMessage", "storedActions", "restoredMessage", "restoreButton"];
  static values = {
    enabled: { type: Boolean, default: false },
    storageKey: String,
    unlockSeed: String,
    clearOnConnect: { type: Boolean, default: false },
    promptWithExistingContent: { type: Boolean, default: false },
    promptDelay: { type: Number, default: 6000 },
    autosaveUrl: String, // set only for server-side draft ideas: typed content is also PATCHed there so lock/reload never loses it
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
    // The lock waits (up to 300ms) on draft:flush; also flush when the tab hides or unloads.
    this.boundFlush = (event) => event.detail?.wait?.push(this.flush());
    this.boundHide = () => document.visibilityState === "hidden" && this.flush(true);
    document.addEventListener("draft:flush", this.boundFlush);
    document.addEventListener("visibilitychange", this.boundHide);
    window.addEventListener("pagehide", this.boundHide);
    this.autoRestore();
  }

  // Local copy is only used when the server copy came back empty (e.g. save never landed).
  async autoRestore() {
    if (!this.autosaveUrlValue || hasMeaningfulDraft(collectDraftFields(this.element))) return;
    if (this.readStoredRecord()) await this.restore();
  }

  async flush(keepalive = false) {
    clearTimeout(this.saveTimer);
    clearTimeout(this.serverTimer);
    await this.saveDraft();
    await this.saveToServer(keepalive);
  }

  async saveToServer(keepalive = false) {
    if (!this.autosaveUrlValue || this.discarded || this.submittingAfterSave) return;
    const body = new FormData();
    for (const [name, value] of new FormData(this.element)) {
      if (!(value instanceof File)) body.append(name, value); // ponytail: files (hero images) only go with the final submit
    }
    body.set("autosave", "1");
    if (!hasMeaningfulDraft(collectDraftFields(this.element))) return; // never overwrite the server copy with an empty form
    try {
      await fetch(this.autosaveUrlValue, { method: "POST", body, keepalive, credentials: "same-origin", headers: { Accept: "application/json" } });
    } catch (_error) { /* offline: the encrypted local copy still has it */ }
  }

  disconnect() {
    clearTimeout(this.saveTimer);
    clearTimeout(this.promptTimer);
    clearTimeout(this.serverTimer);
    if (this.boundFlush) {
      document.removeEventListener("draft:flush", this.boundFlush);
      document.removeEventListener("visibilitychange", this.boundHide);
      window.removeEventListener("pagehide", this.boundHide);
    }
    if (this.boundBeforeUnload) window.removeEventListener("beforeunload", this.boundBeforeUnload);
  }

  queueSave() {
    if (!this.enabledValue || this.submittingAfterSave) return;
    this.hidePrompt();
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveDraft(), 350);
    clearTimeout(this.serverTimer);
    this.serverTimer = setTimeout(() => this.saveToServer(), 1500);
    this.queueResumePrompt();
  }

  async submit(event) {
    if (!this.enabledValue || this.submittingAfterSave) return;

    event.preventDefault();
    clearTimeout(this.saveTimer);
    clearTimeout(this.serverTimer);
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
      this.showRestored();
    } catch (_error) {
      this.showError("This saved idea draft cannot be unlocked in the current app session.");
    }
  }

  async discard() {
    const confirmed = await confirmDialog("Discard the saved idea draft on this device? This cannot be undone.", {
      title: "Discard saved draft?",
      confirmLabel: "Discard draft",
      variant: "danger",
    });
    if (!confirmed) return;
    this.discarded = this.restored; // beforeunload must not re-save the form we are about to reset
    this.clearStoredDraft();
    this.hidePrompt();
    if (this.restored) window.location.reload();
  }

  // Restoring must never be silent: say what happened and keep Discard one click away.
  showRestored() {
    this.restored = true;
    this.toggleStoredDraftMode(true);
    if (this.hasStoredMessageTarget) this.storedMessageTarget.hidden = true;
    if (this.hasRestoredMessageTarget) this.restoredMessageTarget.hidden = false;
    if (this.hasRestoreButtonTarget) this.restoreButtonTarget.hidden = true;
    if (this.hasErrorTarget) this.errorTarget.textContent = "";
    if (this.hasPromptTarget) this.promptTarget.hidden = false;
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
    if (this.discarded) return;
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
    alertDialog(message, { title: "Draft couldn’t be protected", confirmLabel: "Got it" });
  }

  cryptoOptions() {
    return {
      storageKey: this.storageKeyValue,
      unlockSeed: this.unlockSeedValue,
    };
  }
}
