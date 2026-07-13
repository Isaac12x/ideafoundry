import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["list", "row", "hideNativeInput", "nativeRow"];

  addRow() {
    const row = document.createElement("div");
    row.className = "kb-folder-entry";
    row.dataset.kbFoldersTarget = "row";
    row.innerHTML = `
      <div class="kb-folder-row">
        <input type="text" name="kb_folders[]" placeholder="/path/to/your/docs" class="kb-folder-input" />
        <button type="button" class="btn btn-sm kb-folder-browse-btn"
                data-action="click->kb-folders#browse" title="Choose folder…">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          Browse
        </button>
        <button type="button" class="btn btn-sm kb-folder-open-btn"
                data-action="click->kb-folders#openFolder" title="Open in Finder" disabled>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
        </button>
        <button type="button" class="btn btn-sm btn-danger kb-folder-remove"
                data-action="click->kb-folders#removeRow" title="Remove">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
    `;
    this.listTarget.appendChild(row);
    const input = row.querySelector("input");
    input.addEventListener("input", () => this.#syncOpenBtn(row));
    input.focus();
  }

  removeRow(event) {
    event.currentTarget.closest("[data-kb-folders-target='row']").remove();
  }

  hideNative() {
    this.hideNativeInputTarget.value = "1";
    this.nativeRowTarget.remove();
  }

  async browse(event) {
    const row = event.currentTarget.closest(".kb-folder-entry");
    const input = row.querySelector("input.kb-folder-input");
    const res = await fetch("/settings/kb/pick-folder", { headers: { Accept: "application/json" } });
    if (!res.ok) return;
    const data = await res.json();
    if (data.path) {
      input.value = data.path;
      this.#syncOpenBtn(row);
    }
  }

  async openFolder(event) {
    const row = event.currentTarget.closest(".kb-folder-entry");
    const path = row.querySelector("input.kb-folder-input")?.value?.trim();
    if (!path) return;
    await fetch("/settings/kb/open-folder", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrfToken() },
      body: JSON.stringify({ path })
    });
  }

  #syncOpenBtn(row) {
    const btn = row.querySelector(".kb-folder-open-btn");
    const val = row.querySelector("input.kb-folder-input")?.value?.trim();
    if (btn) btn.disabled = !val;
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? "";
  }
}
