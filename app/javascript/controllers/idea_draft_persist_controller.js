import { Controller } from "@hotwired/stimulus";
import {
  collectDraftFields,
  decryptDraft,
  encryptDraft,
  hasMeaningfulDraft,
  restoreDraftFields,
} from "../lib/idea_draft_store.mjs";

export default class extends Controller {
  static targets = ["prompt", "savedAt", "error"];
  static values = {
    enabled: { type: Boolean, default: false },
    storageKey: String,
    unlockSeed: String,
    clearOnConnect: { type: Boolean, default: false },
  };

  connect() {
    this.saveTimer = null;
    this.submittingAfterSave = false;

    if (this.clearOnConnectValue) {
      this.clearStoredDraft();
      return;
    }

    if (!this.enabledValue) return;
    this.showResumePromptIfNeeded();
    this.boundBeforeUnload = () => this.saveImmediately();
    window.addEventListener("beforeunload", this.boundBeforeUnload);
  }

  disconnect() {
    clearTimeout(this.saveTimer);
    if (this.boundBeforeUnload) window.removeEventListener("beforeunload", this.boundBeforeUnload);
  }

  queueSave() {
    if (!this.enabledValue || this.submittingAfterSave) return;
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveDraft(), 350);
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

  discard() {
    if (!confirm("Discard the saved idea draft on this device?")) return;
    this.clearStoredDraft();
    this.hidePrompt();
  }

  async showResumePromptIfNeeded() {
    const record = this.readStoredRecord();
    if (!record) return;

    if (this.hasSavedAtTarget) {
      this.savedAtTarget.textContent = record.savedAt ? new Date(record.savedAt).toLocaleString() : "recently";
    }
    if (this.hasPromptTarget) this.promptTarget.hidden = false;
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
    alert(message);
  }

  cryptoOptions() {
    return {
      storageKey: this.storageKeyValue,
      unlockSeed: this.unlockSeedValue,
    };
  }
}
