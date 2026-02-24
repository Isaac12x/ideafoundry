import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selector", "tabCustomFields", "tabPanelsContainer", "orphanedPanel", "orphanedList"]
  static values = {
    currentFields: { type: Array, default: [] },
    fieldValues: { type: Object, default: {} }
  }

  connect() {
    this.captureCurrentValues()
  }

  captureCurrentValues() {
    const fields = {}
    // Iterate all tab panels to gather field values keyed by instance_id (or name fallback)
    this.tabCustomFieldsTargets.forEach(grid => {
      grid.querySelectorAll("[data-custom-field]").forEach(el => {
        const key = el.dataset.fieldInstanceId || el.dataset.customField
        const input = el.querySelector("input, textarea, select")
        if (input) {
          fields[key] = input.type === "checkbox" ? (input.checked ? "true" : "") : input.value
        }
      })
    })
    // Also capture from server-rendered custom fields panel
    this.element.querySelectorAll("[data-custom-field]").forEach(el => {
      const key = el.dataset.fieldInstanceId || el.dataset.customField
      if (fields[key] !== undefined) return // already captured
      const input = el.querySelector("input, textarea, select")
      if (input) {
        fields[key] = input.type === "checkbox" ? (input.checked ? "true" : "") : input.value
      }
    })
    this.fieldValuesValue = fields
  }

  async change(event) {
    const templateId = event.target.value

    // Capture current values before switching
    this.captureCurrentValues()

    if (!templateId) {
      // No template — remove all dynamic tab panels and existing server-rendered ones
      this.removeAllTabPanels()
      this.hideOrphaned()
      return
    }

    try {
      const response = await fetch(`/templates/${templateId}.json`)
      if (!response.ok) throw new Error("Failed to fetch template")
      const template = await response.json()

      this.removeAllTabPanels()
      this.renderTabPanels(template)
      this.currentFieldsValue = template.field_definitions
    } catch (e) {
      console.error("Template switch error:", e)
    }
  }

  removeAllTabPanels() {
    // Remove server-rendered tab panels
    this.element.querySelectorAll("[data-tab-panel]").forEach(el => el.remove())
    // Remove server-rendered custom fields panel
    this.element.querySelectorAll("[data-template-switch-target='customFieldsPanel']").forEach(el => el.remove())
    // Clear dynamic container
    if (this.hasTabPanelsContainerTarget) {
      this.tabPanelsContainerTarget.innerHTML = ""
    }
  }

  renderTabPanels(template) {
    const oldValues = { ...this.fieldValuesValue }
    const matched = new Set()
    const tabDefs = (template.tab_definitions || []).sort((a, b) => (a.position || 0) - (b.position || 0))
    const fieldDefs = template.field_definitions || []

    // Default tab
    const defaultTab = tabDefs.length > 0 ? tabDefs[0].name : "general"

    // Group fields by tab
    const grouped = {}
    tabDefs.forEach(t => { grouped[t.name] = [] })
    fieldDefs.forEach(field => {
      const tab = field.tab || defaultTab
      if (!grouped[tab]) grouped[tab] = []
      grouped[tab].push(field)
    })

    // Sort fields within each tab by position
    Object.values(grouped).forEach(fields =>
      fields.sort((a, b) => (a.position || 0) - (b.position || 0))
    )

    // Build HTML for each tab panel
    const container = this.hasTabPanelsContainerTarget ? this.tabPanelsContainerTarget : null
    if (!container) return

    tabDefs.forEach(tab => {
      const fields = grouped[tab.name] || []
      if (fields.length === 0) return

      let fieldsHtml = ""
      fields.forEach(field => {
        const instanceId = field.instance_id || field.name
        // Try exact match by instance_id first, then fuzzy match by name
        let value = oldValues[instanceId]
        if (value === undefined) {
          value = oldValues[field.name]
        }
        if (value === undefined) {
          value = field.default_value || ""
        }
        if (oldValues[instanceId] !== undefined) {
          matched.add(instanceId)
        }
        if (oldValues[field.name] !== undefined) {
          matched.add(field.name)
        }
        fieldsHtml += this.buildFieldHtml(field, value)
      })

      const panelHtml = `
        <div class="form-panel form-section-draggable" data-tab-panel="${tab.name}">
          <h3 class="form-panel-title">${tab.label || tab.name}</h3>
          <div class="weight-grid" data-template-switch-target="tabCustomFields" data-tab-name="${tab.name}">
            ${fieldsHtml}
          </div>
        </div>
      `
      container.insertAdjacentHTML("beforeend", panelHtml)
    })

    // Find orphaned values
    const orphaned = []
    for (const [key, value] of Object.entries(oldValues)) {
      if (!matched.has(key) && value && value.trim() !== "") {
        orphaned.push({ name: key, value })
      }
    }

    if (orphaned.length > 0) {
      this.showOrphaned(orphaned)
    } else {
      this.hideOrphaned()
    }
  }

  buildFieldHtml(field, value) {
    const label = field.label || field.name.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())
    const required = field.required ? 'required' : ''
    const escapedValue = this.escapeHtml(value || "")
    const instanceId = field.instance_id || field.name
    const name = `idea[metadata][${instanceId}]`

    let inputHtml = ""

    switch (field.type) {
      case "textarea":
        inputHtml = `<textarea name="${name}" class="weight-input" style="text-align:left;min-height:80px;" placeholder="${field.placeholder || ""}" ${required}>${escapedValue}</textarea>`
        break
      case "select":
        const options = (field.options || []).map(opt =>
          `<option value="${opt}" ${opt === value ? "selected" : ""}>${opt}</option>`
        ).join("")
        inputHtml = `<select name="${name}" class="weight-input" ${required}><option value="">Select...</option>${options}</select>`
        break
      case "number":
        inputHtml = `<input type="number" name="${name}" value="${escapedValue}" class="weight-input" ${required}>`
        break
      case "boolean":
        const checked = value === "true" || value === true ? "checked" : ""
        inputHtml = `<label style="display:flex;align-items:center;gap:8px;cursor:pointer;"><input type="checkbox" name="${name}" value="true" ${checked}> ${label}</label>`
        return `<div class="weight-item" data-custom-field="${instanceId}" data-field-instance-id="${instanceId}">${inputHtml}</div>`
      case "date":
        inputHtml = `<input type="date" name="${name}" value="${escapedValue}" class="weight-input" ${required}>`
        break
      default: // text
        inputHtml = `<input type="text" name="${name}" value="${escapedValue}" class="weight-input" style="text-align:left;" placeholder="${field.placeholder || ""}" ${required}>`
    }

    return `
      <div class="weight-item" data-custom-field="${instanceId}" data-field-instance-id="${instanceId}">
        <label class="weight-label">
          ${label}
          ${field.required ? '<span style="color:var(--danger)">*</span>' : ""}
        </label>
        <div class="weight-input-group">${inputHtml}</div>
      </div>
    `
  }

  showOrphaned(items) {
    if (!this.hasOrphanedPanelTarget) return

    this.orphanedPanelTarget.style.display = "block"

    let html = ""
    items.forEach(item => {
      const label = item.name.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())
      html += `
        <div class="orphaned-item" draggable="true"
             data-action="dragstart->template-switch#dragStart"
             data-field-name="${item.name}"
             data-field-value="${this.escapeHtml(item.value)}">
          <div class="orphaned-label">${label}</div>
          <div class="orphaned-value">${this.escapeHtml(item.value)}</div>
        </div>
      `
    })

    this.orphanedListTarget.innerHTML = html
  }

  hideOrphaned() {
    if (this.hasOrphanedPanelTarget) {
      this.orphanedPanelTarget.style.display = "none"
      this.orphanedListTarget.innerHTML = ""
    }
  }

  dragStart(event) {
    const el = event.currentTarget
    event.dataTransfer.setData("text/plain", el.dataset.fieldValue)
    event.dataTransfer.setData("application/x-field-name", el.dataset.fieldName)
    el.classList.add("dragging")

    // Highlight drop targets across all tab panels
    this.tabCustomFieldsTargets.forEach(grid => {
      grid.querySelectorAll("[data-custom-field]").forEach(target => {
        target.classList.add("drop-target-highlight")
        target.addEventListener("dragover", this.allowDrop)
        target.addEventListener("drop", this.handleDrop.bind(this))
      })
    })
  }

  allowDrop(event) {
    event.preventDefault()
    event.currentTarget.classList.add("drop-target-active")
  }

  handleDrop(event) {
    event.preventDefault()
    const value = event.dataTransfer.getData("text/plain")
    const sourceName = event.dataTransfer.getData("application/x-field-name")
    const target = event.currentTarget
    const input = target.querySelector("input, textarea, select")

    if (input) {
      if (input.value && input.value.trim() !== "") {
        if (input.tagName === "TEXTAREA") {
          input.value += "\n\n--- From " + sourceName.replace(/_/g, " ") + " ---\n" + value
        } else {
          input.value = value
        }
      } else {
        input.value = value
      }
    }

    // Remove the orphaned item
    const orphanedItem = this.orphanedListTarget.querySelector(`[data-field-name="${sourceName}"]`)
    if (orphanedItem) {
      orphanedItem.remove()
    }

    // Hide panel if no more orphans
    if (this.orphanedListTarget.children.length === 0) {
      this.hideOrphaned()
    }

    // Clean up highlights across all tab panels
    this.tabCustomFieldsTargets.forEach(grid => {
      grid.querySelectorAll("[data-custom-field]").forEach(el => {
        el.classList.remove("drop-target-highlight", "drop-target-active")
        el.removeEventListener("dragover", this.allowDrop)
      })
    })
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
