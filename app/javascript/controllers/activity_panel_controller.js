import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel", "frame"];

  connect() {
    this._onKeyDown = this._onKeyDown.bind(this);
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeyDown);
    document.body.style.overflow = "";
  }

  open() {
    if (!this.hasPanelTarget) return;

    if (this.hasFrameTarget && !this.frameTarget.src) {
      this.frameTarget.src = this.frameTarget.dataset.activityPanelUrlValue;
    }

    if (!this.panelTarget.classList.contains("is-open")) this._trigger = document.activeElement;
    this.panelTarget.classList.add("is-open");
    this.panelTarget.setAttribute("aria-hidden", "false");
    document.addEventListener("keydown", this._onKeyDown);
    document.body.style.overflow = "hidden";
  }

  close() {
    if (!this.hasPanelTarget) return;

    this.panelTarget.classList.remove("is-open");
    this.panelTarget.setAttribute("aria-hidden", "true");
    document.removeEventListener("keydown", this._onKeyDown);
    document.body.style.overflow = "";
    if (this._trigger?.isConnected) this._trigger.focus?.({ preventScroll: true });
    this._trigger = null;
  }

  reload() {
    if (this.hasFrameTarget && this.frameTarget.src) {
      this.frameTarget.reload();
    }
  }

  _onKeyDown(event) {
    if (event.key === "Escape") this.close();
  }
}
