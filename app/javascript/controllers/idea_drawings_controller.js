import { Controller } from "@hotwired/stimulus";
import { confirmDialog, alertDialog } from "lib/app_dialog"
import { loadExcalidrawAssets } from "lib/excalidraw_loader";

// Manages drawings within the idea form: opens an Excalidraw modal to
// create/edit drawings, refreshes thumbnails after save, deletes on demand.
//
// Targets:
//   - list:   container holding rendered thumbnails
//   - empty:  empty-state element shown when no drawings exist
//   - modal:  the modal overlay element (hidden by default)
//   - mount:  inner div the React app attaches to
//   - itemTemplate: optional <template> of a tile (hero panel); else the classic thumbnail markup
//
// The modal is moved to <body> while connected: <main> carries a CSS filter (display
// contrast), which makes it the containing block of position:fixed descendants and
// pushed the editor off-screen in the middle of the long form.
//
// The React root stays mounted between openings (re-opening only swaps the scene) and a
// pending debounced save is flushed on close, so open/close are cheap and nothing is lost.
//
// Values:
//   - role: "general" | "hero" | "attachment"
//   - createUrl: POST endpoint for new drawings
//   - showUrlPattern: pattern with __ID__ for show/update/destroy
//   - thumbnailMode: "list" | "single"  (single = only one drawing slot)
export default class extends Controller {
  static targets = ["list", "empty", "modal", "mount", "itemTemplate"];
  static values = {
    role: String,
    createUrl: String,
    showUrlPattern: String,
    thumbnailMode: { type: String, default: "list" },
    bundleUrl: String,
    stylesheetUrl: String,
  };

  connect() {
    this.boundSaved = this._onSaved.bind(this);
    this.element.addEventListener("drawing:saved", this.boundSaved);
    this.boundReady = this._mountIfPending.bind(this);
    document.addEventListener("excalidraw:ready", this.boundReady);

    // Portal the modal to <body> (see header); wire its own events since it leaves our scope.
    this.modal = this.hasModalTarget ? this.modalTarget : null;
    this.mount = this.hasMountTarget ? this.mountTarget : null;
    if (this.modal) {
      this.boundModalClick = (e) => {
        if (e.target === this.modal || e.target.closest("[data-modal-close]")) this._closeMount();
      };
      this.modal.addEventListener("click", this.boundModalClick);
      this.modal.addEventListener("drawing:saved", this.boundSaved); // the mount lives in <body> now
      this.boundDrawingReady = () => this._measure("open", "drawing-open", "drawing-ready");
      this.modal.addEventListener("drawing:ready", this.boundDrawingReady);
      document.body.appendChild(this.modal);
      this.boundBeforeCache = () => this.element.appendChild(this.modal);
      document.addEventListener("turbo:before-cache", this.boundBeforeCache);
    }
    this._idlePrefetch();
  }

  disconnect() {
    this.element.removeEventListener("drawing:saved", this.boundSaved);
    document.removeEventListener("excalidraw:ready", this.boundReady);
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache);
    if (this._idleHandle && window.cancelIdleCallback) window.cancelIdleCallback(this._idleHandle);
    if (this.modal) {
      this.modal.removeEventListener("click", this.boundModalClick);
      this.modal.removeEventListener("drawing:saved", this.boundSaved);
      this.modal.removeEventListener("drawing:ready", this.boundDrawingReady);
      this.modal.remove();
      document.body.classList.remove("modal-open");
    }
    this._unmount();
  }

  // ---- Prefetch ----

  // Idle: let the browser download + compile the 9MB bundle (modulepreload doesn't execute it).
  _idlePrefetch() {
    if (!this.bundleUrlValue || window.IdeaApp?.mountExcalidraw) return;
    const run = () => {
      this._preload("modulepreload", this.bundleUrlValue);
      if (this.stylesheetUrlValue) this._preload("preload", this.stylesheetUrlValue, "style");
    };
    this._idleHandle = window.requestIdleCallback ? window.requestIdleCallback(run, { timeout: 4000 }) : setTimeout(run, 2000);
  }

  _preload(rel, href, as) {
    if (document.querySelector(`link[rel="${rel}"][href="${href}"]`)) return;
    const link = document.createElement("link");
    link.rel = rel;
    link.href = href;
    if (as) link.as = as;
    document.head.appendChild(link);
  }

  // Hover/focus intent on the open button: evaluate the bundle now so the click only mounts.
  prefetch() {
    if (this.bundleUrlValue) loadExcalidrawAssets(this.bundleUrlValue, this.stylesheetUrlValue).catch(() => {});
  }

  // ---- Modal lifecycle ----

  open(event) {
    if (event) event.preventDefault();
    performance.mark("drawing-open");
    this._openMount({});
  }

  async edit(event) {
    if (event) event.preventDefault();
    performance.mark("drawing-open");
    const btn = event.currentTarget;
    const id = btn.dataset.drawingId;
    const url = this.showUrlPatternValue.replace("__ID__", id);
    let title = btn.dataset.drawingTitle || "Untitled";
    let content = "{}";
    // Fetch the scene while the bundle loads (a no-op wait when it is already evaluated).
    const assets = this._assets();
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
    await assets;
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
    if (event.target === this.modal) this._closeMount();
  }

  closeOnEsc(event) {
    if (event.key === "Escape" && this.modal && !this.modal.classList.contains("hidden")) {
      this._closeMount();
    }
  }

  async delete(event) {
    event.preventDefault();
    const btn = event.currentTarget;
    const confirmed = await confirmDialog("Delete this drawing? This cannot be undone.", {
      title: "Delete drawing?",
      confirmLabel: "Delete drawing",
      variant: "danger",
    });
    if (!confirmed) return;

    const url = this.showUrlPatternValue.replace("__ID__", btn.dataset.drawingId);
    let res;
    try {
      res = await fetch(url, {
        method: "DELETE",
        headers: { "Accept": "application/json", "X-CSRF-Token": this._csrf() },
      });
    } catch {
      alertDialog("The drawing could not be deleted. Try again.", { title: "Delete failed", confirmLabel: "Got it" });
      return;
    }
    if (res.ok) {
      const item = btn.closest("[data-drawing-item]");
      if (item) item.remove();
      this._refreshEmptyState();
    }
  }

  // ---- Internals ----

  _assets() {
    return this.bundleUrlValue ? loadExcalidrawAssets(this.bundleUrlValue, this.stylesheetUrlValue) : Promise.resolve();
  }

  async _openMount(opts) {
    await this._assets();

    const mount = this.mount;
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

    this.modal.classList.remove("hidden");
    document.body.classList.add("modal-open");
    this._mountPending = true;
    this._mountIfPending();
  }

  _mountIfPending() {
    if (!this._mountPending) return;
    const fn = window.IdeaApp?.mountExcalidraw;
    if (!fn) return;
    fn(this.mount); // first call creates the root; later calls only swap the scene
    this._mountPending = false;
  }

  _closeMount() {
    if (!this.modal || this.modal.classList.contains("hidden")) return;
    performance.mark("drawing-close");
    this.modal.classList.add("hidden");
    document.body.classList.remove("modal-open");
    this._mountPending = false;
    // Hidden first (form is usable at once); the save + thumbnail refresh follow.
    window.IdeaApp?.flushExcalidraw?.(this.mount);
    requestAnimationFrame(() => this._measure("close", "drawing-close", "drawing-closed"));
  }

  // open: click -> editor showing the scene; close: click -> form visible again.
  // Read from the console: window.__drawingTimings
  _measure(label, from, to) {
    performance.mark(to);
    const ms = performance.measure(`drawing-${label}`, from, to).duration;
    (window.__drawingTimings ||= []).push({ label, ms: Math.round(ms) });
  }

  _unmount() {
    if (window.IdeaApp?.unmountExcalidraw && this.mount) {
      window.IdeaApp.unmountExcalidraw(this.mount);
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
    if (this.hasItemTemplateTarget) return this._upsertTile(item, data);
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
        ${png ? `<img src="${this._esc(png)}" alt="${this._esc(title)}" />` : `<div class="drawing-thumb__placeholder">No preview</div>`}
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

  // Hero tile: clone the server-rendered template for a new drawing, else refresh the existing tile.
  _upsertTile(item, data) {
    const id = String(data.id);
    if (!item) {
      item = this.itemTemplateTarget.content.firstElementChild.cloneNode(true);
      item.dataset.drawingId = id;
      item.dataset.heroKey = `drawing:${id}`;
      item.querySelector("[data-slot=order]").value = `drawing:${id}`;
      item.querySelectorAll("[data-drawing-id]").forEach((el) => (el.dataset.drawingId = id));
      this.listTarget.appendChild(item);
    }
    const title = data.title || "Untitled";
    item.querySelector("[data-slot=title]").textContent = title;
    item.querySelector("[data-slot=edit]").dataset.drawingTitle = title;
    if (data.png_url) {
      const media = item.querySelector("[data-slot=media]");
      let img = media.querySelector("img");
      if (!img) {
        media.textContent = "";
        img = document.createElement("img");
        img.draggable = false;
        media.appendChild(img);
      }
      img.alt = title;
      img.src = data.png_url;
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
