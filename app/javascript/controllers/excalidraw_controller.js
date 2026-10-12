import { Controller } from "@hotwired/stimulus";
import { loadExcalidrawAssets } from "lib/excalidraw_loader";

// Mounts the Excalidraw React app on connect and unmounts on disconnect so
// Turbo navigations always render a fresh canvas.
export default class extends Controller {
  static values = {
    bundleUrl: String,
    stylesheetUrl: String,
  };

  async connect() {
    this._gone = false;
    await this._ensureAssets();
    if (this._gone) return;
    this.boundMount = this._tryMount.bind(this);
    if (this._tryMount()) return;

    document.addEventListener("excalidraw:ready", this.boundMount, { once: true });
    this._poll = setInterval(() => {
      if (this._tryMount()) {
        clearInterval(this._poll);
        this._poll = null;
      }
    }, 100);
  }

  disconnect() {
    this._gone = true;
    if (this._poll) {
      clearInterval(this._poll);
      this._poll = null;
    }
    if (this.boundMount) {
      document.removeEventListener("excalidraw:ready", this.boundMount);
    }
    if (window.IdeaApp?.unmountExcalidraw) {
      window.IdeaApp.unmountExcalidraw(this.element);
    }
  }

  async _ensureAssets() {
    if (!this.bundleUrlValue) return;
    await loadExcalidrawAssets(this.bundleUrlValue, this.stylesheetUrlValue);
  }

  _tryMount() {
    const fn = window.IdeaApp?.mountExcalidraw;
    if (!fn) return false;
    fn(this.element);
    return true;
  }
}
