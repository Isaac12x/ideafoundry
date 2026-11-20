import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "descRow", "descToggle"]

  reset(event) {
    if (event?.detail && !event.detail.success) return // a rejected save keeps what was typed
    this.element.reset()
    if (this.hasDescRowTarget) {
      this.descRowTarget.style.display = "none"
    }
    if (this.hasDescToggleTarget) {
      this.descToggleTarget.innerHTML = `
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
        Add details
      `
    }
    // The stream swaps in a fresh form right after submit-end: focus whichever input is live then.
    setTimeout(() => (document.querySelector("#build_item_form [data-build-item-form-target=input]") || (this.hasInputTarget && this.inputTarget))?.focus())
  }

  toggleDesc() {
    if (this.hasDescRowTarget) {
      const hidden = this.descRowTarget.style.display === "none"
      this.descRowTarget.style.display = hidden ? "flex" : "none"
      if (this.hasDescToggleTarget) {
        this.descToggleTarget.innerHTML = hidden
          ? `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="5" y1="12" x2="19" y2="12"/></svg> Hide details`
          : `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> Add details`
      }
    }
  }
}
