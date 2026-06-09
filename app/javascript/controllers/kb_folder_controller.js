import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["files"];

  connect() {
    // Start expanded
  }

  toggle() {
    this.element.classList.toggle("is-collapsed");
  }
}
