import { Controller } from "@hotwired/stimulus";

// Polls a knowledge-extraction status endpoint while a job is in flight.
//
// mode "frame" (default, used by KB): reloads the surrounding turbo-frame so the
//   server-rendered panel updates and eventually shows the result.
// mode "json" (used by the idea sidebar): fetches JSON and updates the label /
//   progress targets in place; on completion reloads the page so the freshly
//   produced markdown attachment and search index appear.
export default class extends Controller {
  static values = {
    url: String,
    active: Boolean,
    mode: { type: String, default: "frame" },
    interval: { type: Number, default: 4000 },
  };
  static targets = ["label", "progress"];

  connect() {
    if (!this.activeValue) return;
    this._timer = setInterval(() => this._refresh(), this.intervalValue);
  }

  disconnect() {
    if (this._timer) clearInterval(this._timer);
  }

  _refresh() {
    if (this.modeValue === "json") {
      this._refreshJson();
    } else {
      this._reloadFrame();
    }
  }

  async _refreshJson() {
    try {
      const resp = await fetch(this.urlValue, { headers: { Accept: "application/json" } });
      const data = await resp.json();
      if (this.hasLabelTarget) {
        this.labelTarget.textContent = this._label(data);
      }
      if (this.hasProgressTarget && data.progress != null) {
        this.progressTarget.value = data.progress;
      }
      if (["complete", "failed", "canceled"].includes(data.status)) {
        clearInterval(this._timer);
        if (data.status === "complete") window.Turbo?.visit(window.location.href, { action: "replace" });
      }
    } catch {
      /* keep polling */
    }
  }

  _label(data) {
    const status = (data.status || "").replace(/_/g, " ");
    if (data.page_count) return `${status} — page ${data.pages_done || 0}/${data.page_count}`;
    return status;
  }

  _reloadFrame() {
    const frame = this.element.closest("turbo-frame");
    if (!frame) return;
    frame.src = this.urlValue;
    if (typeof frame.reload === "function") frame.reload();
  }
}
