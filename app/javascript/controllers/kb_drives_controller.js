import { Controller } from "@hotwired/stimulus";

// Manages the KB drives list on the settings form: add a mounted volume as a
// kb_drives[] row, or remove one. Saved with the rest of the form.
export default class extends Controller {
  static targets = ["list", "volume"];

  addVolume() {
    const path = this.volumeTarget.value;
    if (!path) return;
    if (this.#existing().includes(path)) return;

    const row = document.createElement("div");
    row.className = "kb-folder-entry kb-drive-entry";
    row.innerHTML = `
      <div class="kb-folder-row">
        <input type="text" name="kb_drives[]" value="${path}" class="kb-folder-input" readonly />
        <span class="kb-folder-native-badge">Mounted</span>
        <button type="button" class="btn btn-sm btn-danger kb-folder-remove"
                data-action="click->kb-drives#remove" title="Remove">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>`;
    this.listTarget.insertBefore(row, this.listTarget.querySelector(".kb-drive-row"));
    this.volumeTarget.value = "";
    this.#notifyChange();
  }

  remove(event) {
    event.currentTarget.closest(".kb-drive-entry").remove();
    this.#notifyChange();
  }

  // JS mutations don't emit change; fire one so form-level autosave sees it
  #notifyChange() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  #existing() {
    return Array.from(this.listTarget.querySelectorAll("input[name='kb_drives[]']")).map((i) => i.value);
  }
}
