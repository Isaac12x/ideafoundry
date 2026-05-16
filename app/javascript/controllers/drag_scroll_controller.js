import { Controller } from "@hotwired/stimulus";

// Drag-to-scroll for horizontally overflowing containers (e.g. tab bars).
// Click events on inner elements are suppressed when a real drag occurred so
// scrolling doesn't accidentally activate a tab.
export default class extends Controller {
  connect() {
    this.isDown = false;
    this.moved = false;
    this.startX = 0;
    this.scrollLeft = 0;

    this._down = this.onDown.bind(this);
    this._move = this.onMove.bind(this);
    this._up = this.onUp.bind(this);
    this._click = this.onClick.bind(this);
    this._cancel = this.onCancel.bind(this);

    this.element.addEventListener("mousedown", this._down);
    window.addEventListener("mousemove", this._move);
    window.addEventListener("mouseup", this._up);
    window.addEventListener("blur", this._cancel);
    this.element.addEventListener("click", this._click, true);
    this.element.classList.add("drag-scroll");
  }

  disconnect() {
    this.element.removeEventListener("mousedown", this._down);
    window.removeEventListener("mousemove", this._move);
    window.removeEventListener("mouseup", this._up);
    window.removeEventListener("blur", this._cancel);
    this.element.removeEventListener("click", this._click, true);
  }

  onDown(e) {
    if (e.button !== 0) return;
    this.isDown = true;
    this.moved = false;
    this.startX = e.pageX;
    this.scrollLeft = this.element.scrollLeft;
  }

  onMove(e) {
    if (!this.isDown) return;
    const walk = e.pageX - this.startX;
    if (Math.abs(walk) > 4) {
      this.moved = true;
      this.element.classList.add("is-dragging");
    }
    this.element.scrollLeft = this.scrollLeft - walk;
  }

  onUp() {
    if (!this.isDown) return;
    this.reset();
  }

  onCancel() {
    if (this.isDown) this.reset();
  }

  reset() {
    this.isDown = false;
    this.element.classList.remove("is-dragging");
  }

  onClick(e) {
    if (this.moved) {
      e.preventDefault();
      e.stopPropagation();
      this.moved = false;
    }
  }
}
