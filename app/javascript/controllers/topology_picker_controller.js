import { Controller } from "@hotwired/stimulus"

// Collapsible, searchable topology tree in the idea form.
// Search reveals matching nodes plus their ancestors and descendants;
// clearing the box restores the fully-expanded tree.
export default class extends Controller {
  static targets = ["search", "tree", "empty", "newToggle", "newPanel", "newName", "newParent", "newError"]
  static values = { createUrl: String }

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

  preventSubmit(event) { event.preventDefault() }

  // ---- inline "+ New topology": POST JSON, insert the node, auto-select it ----
  toggleNew() {
    const open = this.newPanelTarget.hidden
    this.newPanelTarget.hidden = !open
    this.newToggleTarget.setAttribute("aria-expanded", String(open))
    this.showError("")
    if (open) this.newNameTarget.focus()
  }

  newKeydown(event) {
    if (event.key === "Enter") { event.preventDefault(); this.createTopology() }
  }

  // Escape anywhere in the open panel collapses it and returns focus to the toggle.
  collapseNew(event) {
    if (event.key !== "Escape" || this.newPanelTarget.hidden) return
    event.preventDefault()
    event.stopPropagation()
    this.toggleNew()
    this.newToggleTarget.focus()
  }

  async createTopology() {
    const name = this.newNameTarget.value.trim()
    if (!name) return this.showError("Name can't be blank")
    const parentId = this.newParentTarget.value
    this.showError("")
    let response, data
    try {
      response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify({ topology: { name, parent_id: parentId || null } })
      })
      data = await response.json()
    } catch (_e) {
      return this.showError("Could not create topology")
    }
    if (!response.ok) {
      const errors = data.errors || {}
      return this.showError(Object.entries(errors).map(([k, v]) => `${k === "name" ? "Name" : k} ${[].concat(v).join(", ")}`).join("; ") || "Could not create topology")
    }

    const node = this.insertNode(data, parentId)
    const option = new Option(data.full_path, data.id)
    this.newParentTarget.add(option)
    this.newNameTarget.value = ""
    this.newParentTarget.value = ""
    this.emptyTarget.hidden = true
    this.searchTarget.value = ""
    this.filter()
    const box = node.querySelector("input[type=checkbox]")
    box.checked = true
    box.dispatchEvent(new Event("change", { bubbles: true })) // template-switch + draft persist
    node.scrollIntoView({ block: "nearest" })
    this.toggleNew() // done: collapse again, focus the new checkbox
    box.focus()
  }

  insertNode(data, parentId) {
    const holder = document.createElement("div")
    holder.innerHTML = data.html.trim()
    const node = holder.firstElementChild
    const parent = parentId && this.treeTarget.querySelector(`#topology_${CSS.escape(parentId)}`)?.closest(".topology-node")
    if (!parent) { this.treeTarget.append(node); return node }

    let kids = parent.querySelector(":scope > .topology-node__children")
    if (!kids) {
      kids = document.createElement("div")
      kids.className = "topology-node__children"
      parent.append(kids)
      const leaf = parent.querySelector(":scope > .topology-node__row > .topology-node__toggle--leaf")
      const toggle = document.createElement("button")
      toggle.type = "button"
      toggle.className = "topology-node__toggle"
      toggle.setAttribute("aria-expanded", "true")
      toggle.setAttribute("aria-label", "Expand or collapse children")
      toggle.dataset.action = "topology-picker#toggleNode"
      toggle.innerHTML = leaf.innerHTML || '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m9 18 6-6-6-6"/></svg>'
      leaf.replaceWith(toggle)
    }
    parent.classList.remove("is-collapsed")
    kids.append(node)
    return node
  }

  showError(message) {
    this.newErrorTarget.textContent = message
    this.newErrorTarget.hidden = !message
  }
}
