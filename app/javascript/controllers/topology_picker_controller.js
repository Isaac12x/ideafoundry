import { Controller } from "@hotwired/stimulus"

// Collapsible, searchable topology tree in the idea form.
// Search reveals matching nodes plus their ancestors and descendants;
// clearing the box restores the fully-expanded tree.
export default class extends Controller {
  static targets = ["search", "tree", "empty"]

  toggleNode(event) {
    const node = event.currentTarget.closest(".topology-node")
    const collapsed = node.classList.toggle("is-collapsed")
    event.currentTarget.setAttribute("aria-expanded", String(!collapsed))
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    const nodes = this.treeTarget.querySelectorAll(".topology-node")

    if (!query) {
      nodes.forEach((node) => {
        node.hidden = false
        this._setExpanded(node, true)
      })
      this.emptyTarget.hidden = true
      return
    }

    nodes.forEach((node) => (node.hidden = true))
    let anyMatch = false

    nodes.forEach((node) => {
      if (!node.dataset.topologyName.includes(query)) return
      anyMatch = true

      // Reveal + expand the node and every ancestor so the path stays visible.
      let current = node
      while (current && current.classList.contains("topology-node")) {
        current.hidden = false
        this._setExpanded(current, true)
        current = current.parentElement.closest(".topology-node")
      }
      // Reveal descendants of a matched node too.
      node.querySelectorAll(".topology-node").forEach((child) => (child.hidden = false))
    })

    this.emptyTarget.hidden = anyMatch
  }

  _setExpanded(node, expanded) {
    node.classList.toggle("is-collapsed", !expanded)
    const toggle = node.querySelector(":scope > .topology-node__row > .topology-node__toggle")
    if (toggle && toggle.tagName === "BUTTON") {
      toggle.setAttribute("aria-expanded", String(expanded))
    }
  }
}
