import { Controller } from "@hotwired/stimulus";

// Manages drawings within the idea form: opens an Excalidraw modal to
// create/edit drawings, refreshes thumbnails after save, deletes on demand.
//
// Targets:
//   - list:   container holding rendered thumbnails
//   - empty:  empty-state element shown when no drawings exist
//   - modal:  the modal overlay element (hidden by default)
//   - mount:  inner div the React app attaches to
//
// Values:
//   - role: "general" | "hero" | "attachment"
//   - createUrl: POST endpoint for new drawings
//   - showUrlPattern: pattern with __ID__ for show/update/destroy
//   - thumbnailMode: "list" | "single"  (single = only one drawing slot, e.g. hero)
export default class extends Controller {
  static targets = ["list", "empty", "modal", "mount", "fileToggle", "drawToggle", "filePanel", "drawPanel"];
  static values = {
    role: String,
    createUrl: String,
    showUrlPattern: String,
    thumbnailMode: { type: String, default: "list" }
  };

  connect() {
    this.boundSaved = this._onSaved.bind(this);
    this.element.addEventListener("drawing:saved", this.boundSaved);
    this.boundReady = this._mountIfPending.bind(this);
    document.addEventListener("excalidraw:ready", this.boundReady);
  }

  disconnect() {
    this.element.removeEventListener("drawing:saved", this.boundSaved);
    document.removeEventListener("excalidraw:ready", this.boundReady);
    this._unmount();
  }

  // ---- Modal lifecycle ----

  open(event) {
    if (event) event.preventDefault();
    this._openMount({});
  }

  async edit(event) {
    if (event) event.preventDefault();
    const btn = event.currentTarget;
    const id = btn.dataset.drawingId;
    const url = this.showUrlPatternValue.replace("__ID__", id);
    let title = btn.dataset.drawingTitle || "Untitled";
    let content = "{}";
    try {
      const res = await fetch(url, { headers: { "Accept": "application/json" } });
      if (res.ok) {
        const json = await res.json();
        title = json.title || title;
        content = JSON.stringify(json.content || {});
      }
    } catch (e) {
      console.warn("Failed to load drawing for edit:", e);
    }
    this._openMount({
      drawingId: id,
      drawingTitle: title,
      drawingContent: content,
    });
  }

  close(event) {
    if (event) event.preventDefault();
    this._closeMount();
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) this._closeMount();
  }

  closeOnEsc(event) {
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this._closeMount();
    }
  }

  async delete(event) {
    event.preventDefault();
    const btn = event.currentTarget;
    if (!confirm("Delete this drawing?")) return;

    const url = this.showUrlPatternValue.replace("__ID__", btn.dataset.drawingId);
    const res = await fetch(url, {
      method: "DELETE",
      headers: { "Accept": "application/json", "X-CSRF-Token": this._csrf() },
    });
    if (res.ok) {
      const item = btn.closest("[data-drawing-item]");
      if (item) item.remove();
      this._refreshEmptyState();
    }
  }

  // ---- File/Draw toggle (hero/attachment panels) ----

  selectFile(event) {
    if (event) event.preventDefault();
    if (this.hasFilePanelTarget) this.filePanelTarget.classList.remove("hidden");
    if (this.hasDrawPanelTarget) this.drawPanelTarget.classList.add("hidden");
    if (this.hasFileToggleTarget) this.fileToggleTarget.classList.add("active");
    if (this.hasDrawToggleTarget) this.drawToggleTarget.classList.remove("active");
  }

  selectDraw(event) {
    if (event) event.preventDefault();
    if (this.hasFilePanelTarget) this.filePanelTarget.classList.add("hidden");
    if (this.hasDrawPanelTarget) this.drawPanelTarget.classList.remove("hidden");
    if (this.hasFileToggleTarget) this.fileToggleTarget.classList.remove("active");
    if (this.hasDrawToggleTarget) this.drawToggleTarget.classList.add("active");
  }

  // ---- Internals ----

  _openMount(opts) {
    const mount = this.mountTarget;
    this._unmount();

    if (opts.drawingId) {
      mount.dataset.drawingId = opts.drawingId;
      mount.dataset.drawingTitle = opts.drawingTitle || "Untitled";
      mount.dataset.drawingContent = opts.drawingContent || "{}";
    } else {
      delete mount.dataset.drawingId;
      mount.dataset.drawingTitle = "Untitled";
      mount.dataset.drawingContent = "{}";
    }
    mount.dataset.drawingRole = this.roleValue;
    mount.dataset.createUrl = this.createUrlValue;
    mount.dataset.showUrlPattern = this.showUrlPatternValue;
    mount.dataset.standalone = "false";

    this.modalTarget.classList.remove("hidden");
    document.body.classList.add("modal-open");
    this._mountPending = true;
    this._mountIfPending();
  }

  _mountIfPending() {
    if (!this._mountPending) return;
    const fn = window.IdeaApp?.mountExcalidraw;
    if (!fn) return;
    fn(this.mountTarget);
    this._mountPending = false;
  }

  _closeMount() {
    this._unmount();
    this.modalTarget.classList.add("hidden");
    document.body.classList.remove("modal-open");
  }

  _unmount() {
    if (window.IdeaApp?.unmountExcalidraw && this.hasMountTarget) {
      window.IdeaApp.unmountExcalidraw(this.mountTarget);
    }
    this._mountPending = false;
  }

  _onSaved(event) {
    const data = event.detail;
    if (!data) return;
    this._upsertThumbnail(data);
  }

  _upsertThumbnail(data) {
    if (!this.hasListTarget) return;
    const id = String(data.id);
    let item = this.listTarget.querySelector(`[data-drawing-id="${id}"]`);
    if (!item) {
      item = document.createElement("div");
      item.className = "drawing-thumb";
      item.dataset.drawingItem = "";
      item.dataset.drawingId = id;
      this.listTarget.appendChild(item);
    }

    const png = data.png_url || "";
    const title = data.title || "Untitled";
    item.innerHTML = `
      <div class="drawing-thumb__image">
        ${png ? `<img src="${png}" alt="${this._esc(title)}" />` : `<div class="drawing-thumb__placeholder">No preview</div>`}
      </div>
      <div class="drawing-thumb__row">
        <span class="drawing-thumb__title">${this._esc(title)}</span>
        <div class="drawing-thumb__actions">
          <button type="button" class="btn btn-sm"
                  data-action="click->idea-drawings#edit"
                  data-drawing-id="${id}"
                  data-drawing-title="${this._esc(title)}">Edit</button>
          <button type="button" class="btn btn-sm btn-danger"
                  data-action="click->idea-drawings#delete"
                  data-drawing-id="${id}">Delete</button>
        </div>
      </div>
    `;

    this._refreshEmptyState();

    // For "single" mode (hero), only keep the latest one.
    if (this.thumbnailModeValue === "single") {
      this.listTarget.querySelectorAll("[data-drawing-item]").forEach((el) => {
        if (el !== item) el.remove();
      });
    }
  }

  _refreshEmptyState() {
    if (!this.hasEmptyTarget || !this.hasListTarget) return;
    const has = this.listTarget.querySelector("[data-drawing-item]");
    this.emptyTarget.classList.toggle("hidden", !!has);
  }

  _csrf() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") || "" : "";
  }

  _esc(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML.replace(/"/g, "&quot;");
  }
}
