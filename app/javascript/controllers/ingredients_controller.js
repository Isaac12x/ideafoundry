import { Controller } from "@hotwired/stimulus"
import { convert, nextUnit, format } from "lib/ingredient_units"

// Ingredient list from Kb::Ingredients: clicking a quantity badge cycles its unit (g > kg > oz > lb, ml > l > tsp ...).
// Converts from the original value each time, so cycling back to the first unit restores it exactly.
export default class extends Controller {
  static targets = ["qty"]

  connect() {
    this.qtyTargets.forEach((badge) => {
      badge.dataset.origQty ||= badge.dataset.qty
      badge.dataset.origUnit ||= badge.dataset.unit
    })
    this.element.addEventListener("keydown", this.keys = (event) => {
      if ((event.key === "Enter" || event.key === " ") && event.target.matches("[data-action~='click->ingredients#flip']")) {
        event.preventDefault()
        event.target.click()
      }
    })
  }

  disconnect() { this.element.removeEventListener("keydown", this.keys) }

  flip({ currentTarget: badge }) {
    const unit = nextUnit(badge.dataset.unit)
    const value = convert(Number(badge.dataset.origQty), badge.dataset.origUnit, unit)
    badge.dataset.unit = unit
    badge.textContent = `${format(value)} ${unit}`
  }
}
