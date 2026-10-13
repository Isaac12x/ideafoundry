import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-submit"
// Submits the form when a control fires its action (e.g. select change).
export default class extends Controller {
  go() {
    this.element.requestSubmit();
  }
}
