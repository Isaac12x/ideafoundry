import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon"]

  toggle() {
    const list = this.listTarget
    const isHidden = list.classList.contains("completed-items--hidden") || !list.classList.contains("completed-items--visible")

    if (isHidden) {
      list.classList.remove("completed-items--hidden")
      list.classList.add("completed-items--visible")
      this.iconTarget.style.transform = "rotate(180deg)"
    } else {
      list.classList.remove("completed-items--visible")
      list.classList.add("completed-items--hidden")
      this.iconTarget.style.transform = "rotate(0deg)"
    }
  }
}
