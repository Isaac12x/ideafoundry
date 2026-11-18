import { Controller } from "@hotwired/stimulus"

// Header inbox: a native <details>; close on Esc or an outside click.
export default class extends Controller {
  close() { this.element.open = false }

  outside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.close()
  }
}
