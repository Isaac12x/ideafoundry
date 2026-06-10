import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["list", "row"];

  addRow() {
    const row = document.createElement("div");
    row.className = "kb-folder-entry";
    row.dataset.kbFoldersTarget = "row";
    row.innerHTML = `
      <div class="kb-folder-row">
        <input type="text" name="kb_folders[]" placeholder="/path/to/your/docs" class="kb-folder-input" />
        <button type="button" class="btn btn-sm btn-danger kb-folder-remove"
                data-action="click->kb-folders#removeRow" title="Remove">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
    `;
    this.listTarget.appendChild(row);
    row.querySelector("input").focus();
  }

  removeRow(event) {
    event.currentTarget.closest("[data-kb-folders-target='row']").remove();
  }
}
