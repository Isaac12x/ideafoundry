import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="crm-panel"
// Closes the licensor record slide-over by emptying its Turbo frame.
export default class extends Controller {
  close() {
    const frame = document.getElementById("licensor-panel");
    if (frame) frame.innerHTML = "";
  }
}
