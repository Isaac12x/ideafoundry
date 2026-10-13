import { Controller } from "@hotwired/stimulus"

// Gives instant visual feedback on backlog mutations so the UI doesn't appear
// to stall while the Turbo Stream round-trip completes. The server response is
// still authoritative and replaces/removes the element.
export default class extends Controller {
  // Attached to a .backlog-item; buttons inside trigger these on click.
  remove() {
    this.element.classList.add("backlog-item--removing")
  }

  sync() {
    this.element.classList.add("backlog-item--syncing")
  }
}
