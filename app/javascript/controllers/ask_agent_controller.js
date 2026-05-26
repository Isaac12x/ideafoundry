import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "body"]

  open() {
    if (!this.hasDialogTarget) return

    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "open")
    }

    if (this.hasBodyTarget) {
      this.bodyTarget.focus()
    }
  }

  close() {
    if (!this.hasDialogTarget) return
    if (!this.dialogTarget.open) return

    if (typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close()
    } else {
      this.dialogTarget.removeAttribute("open")
    }
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
