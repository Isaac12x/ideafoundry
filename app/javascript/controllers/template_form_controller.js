import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "sectionOrder", "availableSections",
    // Main area
    "unassignedPool", "tabZones", "tabHiddenInputs",
    // Sidebar — tabs
    "tabList", "newTabName", "newTabLabel",
    // Sidebar — field form
    "fieldFormTitle", "fieldName", "fieldLabel", "fieldType",
    "fieldDefault", "fieldPlaceholder", "fieldRequired",
    "fieldOptions", "fieldOptionsGroup", "fieldSubmitBtn", "fieldCancelBtn"
  ];

  connect() {
    this._draggedChip = null;
    this._draggedSection = null;
    this._editingChip = null;
    this.reindexAllFields();
  }

  // ═══════════════════════════════════════════════════════════
  // UNIFIED DRAG OVER / LEAVE — works for both chips & sections
  // ═══════════════════════════════════════════════════════════

  zoneDragOver(event) {
    if (!this._draggedSection && !this._draggedChip) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    event.currentTarget.classList.add("drag-over");
  }

  zoneDragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      event.currentTarget.classList.remove("drag-over");
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION DRAG & DROP
  // ═══════════════════════════════════════════════════════════

  sectionDragStart(event) {
    this._draggedSection = event.currentTarget;
    this._draggedSection.classList.add("dragging");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", "section");
  }

  sectionDragEnd() {
    if (this._draggedSection) {
      this._draggedSection.classList.remove("dragging");
      this._draggedSection = null;
    }
    this._clearAllDragOver();
  }

  sectionDrop(event) {
    if (!this._draggedSection) return;
    event.preventDefault();
    const zone = event.currentTarget;
    zone.classList.remove("drag-over");

    const isPersist = this._draggedSection.dataset.persist === "true";

    if (zone === this.sectionOrderTarget) {
      const itemToInsert = isPersist ? this._cloneSectionItem(this._draggedSection) : this._draggedSection;
      this._insertAtDropPosition(zone, itemToInsert, event, ".tpl-form__section-item", ".tpl-form__sections-empty");
    } else if (zone === this.availableSectionsTarget) {
      // Dropping back into available pool — only for non-persist (items already in section order)
      if (!isPersist) {
        const emptyMsg = zone.querySelector(".tpl-drop-zone__empty");
        zone.insertBefore(this._draggedSection, emptyMsg);
      }
    } else if (zone.classList.contains("tpl-drop-zone--tab") || zone.classList.contains("tpl-drop-zone--unassigned")) {
      // Section item dropped on a tab zone — clone it there
      const itemToInsert = isPersist ? this._cloneSectionItem(this._draggedSection) : this._draggedSection;
      const emptyMsg = zone.querySelector(".tpl-drop-zone__empty");
      zone.insertBefore(itemToInsert, emptyMsg);
    }

    this._draggedSection.classList.remove("dragging");
    this._draggedSection = null;
    this.reindexSectionOrder();
  }

  _cloneSectionItem(original) {
    const clone = original.cloneNode(true);
    clone.classList.remove("dragging");
    delete clone.dataset.persist;
    if (!clone.querySelector(".tpl-form__section-remove")) {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className = "tpl-form__section-remove";
      removeBtn.innerHTML = "&times;";
      removeBtn.dataset.action = "click->template-form#removeSectionItem";
      clone.appendChild(removeBtn);
    }
    return clone;
  }

  removeSectionItem(event) {
    event.stopPropagation();
    const item = event.currentTarget.closest(".tpl-form__section-item");
    if (item) {
      item.remove();
      this.reindexSectionOrder();
    }
  }

  _insertAtDropPosition(zone, item, event, itemSelector, emptySelector) {
    const items = [...zone.querySelectorAll(`${itemSelector}:not(.dragging)`)];
    const afterEl = items.reduce((closest, child) => {
      const box = child.getBoundingClientRect();
      const offset = event.clientY - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) {
        return { offset, element: child };
      }
      return closest;
    }, { offset: Number.NEGATIVE_INFINITY }).element;

    if (afterEl) {
      zone.insertBefore(item, afterEl);
    } else {
      const emptyMsg = zone.querySelector(emptySelector);
      if (emptyMsg) {
        zone.insertBefore(item, emptyMsg);
      } else {
        zone.appendChild(item);
      }
    }
  }

  reindexSectionOrder() {
    // Collect section items from Section Order zone AND from tab zones
    let idx = 0;

    // Remove all existing section_order hidden inputs everywhere
    this.element.querySelectorAll('.section-order-hidden').forEach(i => i.remove());

    // Section Order zone items
    this.sectionOrderTarget.querySelectorAll("input[type=hidden]").forEach(i => i.remove());
    this.sectionOrderTarget.querySelectorAll(".tpl-form__section-item").forEach(item => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.className = "section-order-hidden";
      input.name = `template[section_order][${idx}]`;
      input.value = item.dataset.section;
      item.appendChild(input);
      idx++;
    });

    // Tab zone section items (section items inside tab drop zones)
    this.element.querySelectorAll(".tpl-drop-zone--tab .tpl-form__section-item, .tpl-drop-zone--unassigned .tpl-form__section-item").forEach(item => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.className = "section-order-hidden";
      input.name = `template[section_order][${idx}]`;
      input.value = item.dataset.section;
      item.appendChild(input);
      idx++;
    });

    // Remove hidden inputs from items in the available pool
    this.availableSectionsTarget.querySelectorAll("input[type=hidden]").forEach(i => i.remove());
  }

  // ═══════════════════════════════════════════════════════════
  // TAB MANAGEMENT
  // ═══════════════════════════════════════════════════════════

  addTab() {
    const name = this.newTabNameTarget.value.trim();
    const label = this.newTabLabelTarget.value.trim();
    if (!name) return;

    const item = document.createElement("div");
    item.className = "tpl-sidebar__tab-item";
    item.dataset.tabName = name;
    item.innerHTML = `
      <span class="tpl-sidebar__tab-label">${label || name}</span>
      <button type="button" class="tpl-sidebar__tab-remove" data-action="click->template-form#removeTab" data-tab-name="${name}">&times;</button>
    `;
    this.tabListTarget.appendChild(item);

    const zone = document.createElement("div");
    zone.className = "tpl-drop-zone tpl-drop-zone--tab";
    zone.dataset.tab = name;
    zone.dataset.action = "dragover->template-form#zoneDragOver dragleave->template-form#zoneDragLeave drop->template-form#zoneDrop";
    zone.innerHTML = `
      <div class="tpl-drop-zone__header">${label || name}</div>
      <span class="tpl-drop-zone__empty">Drop fields here</span>
    `;
    this.tabZonesTarget.appendChild(zone);

    this.syncTabHiddenInputs();
    this.newTabNameTarget.value = "";
    this.newTabLabelTarget.value = "";
  }

  removeTab(event) {
    event.stopPropagation();
    const tabName = event.currentTarget.dataset.tabName;

    const items = this.tabListTarget.querySelectorAll(".tpl-sidebar__tab-item");
    if (items.length <= 1) return;

    const zone = this.tabZonesTarget.querySelector(`.tpl-drop-zone--tab[data-tab="${tabName}"]`);
    if (zone) {
      // Move field chips back to unassigned
      zone.querySelectorAll(".tpl-field-chip").forEach(chip => {
        chip.querySelector(".chip-input-tab").value = "";
        chip.dataset.fieldTab = "";
        this.unassignedPoolTarget.insertBefore(chip, this.unassignedPoolTarget.querySelector(".tpl-drop-zone__empty"));
      });
      // Remove section items (they're clones, just delete)
      zone.querySelectorAll(".tpl-form__section-item").forEach(el => el.remove());
      zone.remove();
    }

    const sidebarItem = this.tabListTarget.querySelector(`.tpl-sidebar__tab-item[data-tab-name="${tabName}"]`);
    if (sidebarItem) sidebarItem.remove();

    this.syncTabHiddenInputs();
    this.reindexAllFields();
    this.reindexSectionOrder();
  }

  syncTabHiddenInputs() {
    const container = this.tabHiddenInputsTarget;
    container.innerHTML = "";
    const items = this.tabListTarget.querySelectorAll(".tpl-sidebar__tab-item");
    items.forEach((item, i) => {
      const name = item.dataset.tabName;
      const label = item.querySelector(".tpl-sidebar__tab-label").textContent;
      container.insertAdjacentHTML("beforeend", `
        <input type="hidden" name="template[tab_definitions][${i}][name]" value="${name}">
        <input type="hidden" name="template[tab_definitions][${i}][label]" value="${label}">
        <input type="hidden" name="template[tab_definitions][${i}][position]" value="${i}">
      `);
    });
  }

  // ═══════════════════════════════════════════════════════════
  // UNIFIED DROP — handles both chips and sections in any zone
  // ═══════════════════════════════════════════════════════════

  zoneDrop(event) {
    event.preventDefault();
    const zone = event.currentTarget;
    zone.classList.remove("drag-over");

    // Delegate to the appropriate handler
    if (this._draggedSection) {
      this._handleSectionDropOnZone(zone, event);
    } else if (this._draggedChip) {
      this._handleChipDropOnZone(zone, event);
    }
  }

  _handleSectionDropOnZone(zone) {
    const isPersist = this._draggedSection.dataset.persist === "true";
    const itemToInsert = isPersist ? this._cloneSectionItem(this._draggedSection) : this._draggedSection;
    const emptyMsg = zone.querySelector(".tpl-drop-zone__empty");
    zone.insertBefore(itemToInsert, emptyMsg);

    this._draggedSection.classList.remove("dragging");
    this._draggedSection = null;
    this.reindexSectionOrder();
  }

  _handleChipDropOnZone(zone) {
    const tab = zone.dataset.tab || "";
    this._draggedChip.querySelector(".chip-input-tab").value = tab;
    this._draggedChip.dataset.fieldTab = tab;

    const emptyMsg = zone.querySelector(".tpl-drop-zone__empty");
    zone.insertBefore(this._draggedChip, emptyMsg);

    this._draggedChip.classList.remove("dragging");
    this._draggedChip = null;
    this.reindexAllFields();
  }

  // ═══════════════════════════════════════════════════════════
  // FIELD CRUD (SIDEBAR)
  // ═══════════════════════════════════════════════════════════

  addOrUpdateField() {
    const name = this.fieldNameTarget.value.trim();
    const label = this.fieldLabelTarget.value.trim();
    const type = this.fieldTypeTarget.value;
    if (!name || !type) return;

    const data = {
      name,
      label,
      type,
      default_value: this.fieldDefaultTarget.value.trim(),
      placeholder: this.fieldPlaceholderTarget.value.trim(),
      required: this.fieldRequiredTarget.checked ? "true" : "false",
      options: this.fieldOptionsTarget.value.trim()
    };

    if (this._editingChip) {
      data.instance_id = this._editingChip.dataset.fieldInstanceId || "";
      this.applyDataToChip(this._editingChip, data);
      this._editingChip.classList.remove("selected");
      this._editingChip = null;
    } else {
      data.instance_id = `${name}_${this._hexId()}`;
      const chip = this.buildChip(data, "");
      this.unassignedPoolTarget.insertBefore(chip, this.unassignedPoolTarget.querySelector(".tpl-drop-zone__empty"));
    }

    this.clearFieldForm();
    this.reindexAllFields();
    this.syncAvailableFieldSections();
  }

  editField(event) {
    if (event.target.closest(".tpl-field-chip__remove")) return;

    const chip = event.currentTarget;

    if (this._editingChip) this._editingChip.classList.remove("selected");

    this._editingChip = chip;
    chip.classList.add("selected");

    this.fieldNameTarget.value = chip.dataset.fieldName || "";
    this.fieldLabelTarget.value = chip.dataset.fieldLabel || "";
    this.fieldTypeTarget.value = chip.dataset.fieldType || "text";
    this.fieldDefaultTarget.value = chip.dataset.fieldDefault || "";
    this.fieldPlaceholderTarget.value = chip.dataset.fieldPlaceholder || "";
    this.fieldRequiredTarget.checked = chip.dataset.fieldRequired === "true";
    this.fieldOptionsTarget.value = chip.dataset.fieldOptions || "";

    this.fieldTypeChanged();

    this.fieldFormTitleTarget.textContent = "Edit Field";
    this.fieldSubmitBtnTarget.textContent = "Update Field";
    this.fieldCancelBtnTarget.style.display = "";
  }

  cancelEditField() {
    if (this._editingChip) {
      this._editingChip.classList.remove("selected");
      this._editingChip = null;
    }
    this.clearFieldForm();
  }

  removeField(event) {
    event.stopPropagation();
    const chip = event.target.closest(".tpl-field-chip");
    if (!chip) return;

    if (this._editingChip === chip) {
      this._editingChip = null;
      this.clearFieldForm();
    }

    chip.style.transition = "opacity 0.2s, transform 0.2s";
    chip.style.opacity = "0";
    chip.style.transform = "scale(0.9)";
    setTimeout(() => {
      chip.remove();
      this.reindexAllFields();
      this.syncAvailableFieldSections();
    }, 200);
  }

  fieldTypeChanged() {
    const show = this.fieldTypeTarget.value === "select";
    this.fieldOptionsGroupTarget.style.display = show ? "" : "none";
  }

  clearFieldForm() {
    this.fieldNameTarget.value = "";
    this.fieldLabelTarget.value = "";
    this.fieldTypeTarget.value = "text";
    this.fieldDefaultTarget.value = "";
    this.fieldPlaceholderTarget.value = "";
    this.fieldRequiredTarget.checked = false;
    this.fieldOptionsTarget.value = "";
    this.fieldOptionsGroupTarget.style.display = "none";

    this.fieldFormTitleTarget.textContent = "Add Field";
    this.fieldSubmitBtnTarget.textContent = "Add Field";
    this.fieldCancelBtnTarget.style.display = "none";
  }

  // ═══════════════════════════════════════════════════════════
  // CHIP BUILDER + DATA SYNC
  // ═══════════════════════════════════════════════════════════

  buildChip(data, tab) {
    const div = document.createElement("div");
    div.className = "tpl-field-chip";
    div.draggable = true;
    div.dataset.action = "dragstart->template-form#chipDragStart dragend->template-form#chipDragEnd click->template-form#editField";
    this.setChipDataAttrs(div, data, tab);

    div.innerHTML = `
      <span class="tpl-field-chip__label">${data.label || data.name}</span>
      <span class="tpl-field-chip__type tpl-field-chip__type--${data.type}">${data.type}</span>
      ${data.required === "true" ? '<span class="tpl-field-chip__required">req</span>' : ""}
      <button type="button" class="tpl-field-chip__remove" data-action="click->template-form#removeField">&times;</button>
      <input type="hidden" class="chip-input-name" value="${this.esc(data.name)}">
      <input type="hidden" class="chip-input-label" value="${this.esc(data.label)}">
      <input type="hidden" class="chip-input-type" value="${this.esc(data.type)}">
      <input type="hidden" class="chip-input-default" value="${this.esc(data.default_value)}">
      <input type="hidden" class="chip-input-placeholder" value="${this.esc(data.placeholder)}">
      <input type="hidden" class="chip-input-required" value="${data.required}">
      <input type="hidden" class="chip-input-options" value="${this.esc(data.options)}">
      <input type="hidden" class="chip-input-tab" value="${tab}">
      <input type="hidden" class="chip-input-position" value="0">
      <input type="hidden" class="chip-input-instance-id" value="${this.esc(data.instance_id || "")}">
    `;
    return div;
  }

  applyDataToChip(chip, data) {
    this.setChipDataAttrs(chip, data, chip.querySelector(".chip-input-tab").value);

    chip.querySelector(".tpl-field-chip__label").textContent = data.label || data.name;

    const typeBadge = chip.querySelector(".tpl-field-chip__type");
    typeBadge.textContent = data.type;
    typeBadge.className = `tpl-field-chip__type tpl-field-chip__type--${data.type}`;

    let reqBadge = chip.querySelector(".tpl-field-chip__required");
    if (data.required === "true") {
      if (!reqBadge) {
        const btn = chip.querySelector(".tpl-field-chip__remove");
        reqBadge = document.createElement("span");
        reqBadge.className = "tpl-field-chip__required";
        reqBadge.textContent = "req";
        btn.before(reqBadge);
      }
    } else if (reqBadge) {
      reqBadge.remove();
    }

    chip.querySelector(".chip-input-name").value = data.name;
    chip.querySelector(".chip-input-label").value = data.label;
    chip.querySelector(".chip-input-type").value = data.type;
    chip.querySelector(".chip-input-default").value = data.default_value;
    chip.querySelector(".chip-input-placeholder").value = data.placeholder;
    chip.querySelector(".chip-input-required").value = data.required;
    chip.querySelector(".chip-input-options").value = data.options;
    if (data.instance_id !== undefined) {
      chip.querySelector(".chip-input-instance-id").value = data.instance_id;
    }
  }

  setChipDataAttrs(chip, data, tab) {
    chip.dataset.fieldName = data.name;
    chip.dataset.fieldLabel = data.label;
    chip.dataset.fieldType = data.type;
    chip.dataset.fieldDefault = data.default_value;
    chip.dataset.fieldPlaceholder = data.placeholder;
    chip.dataset.fieldRequired = data.required;
    chip.dataset.fieldOptions = data.options;
    chip.dataset.fieldTab = tab;
    chip.dataset.fieldInstanceId = data.instance_id || "";
  }

  esc(str) {
    if (!str) return "";
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  _hexId() {
    return Array.from(crypto.getRandomValues(new Uint8Array(4)))
      .map(b => b.toString(16).padStart(2, "0")).join("");
  }

  // ═══════════════════════════════════════════════════════════
  // AVAILABLE FIELD SECTIONS (sync with field chips)
  // ═══════════════════════════════════════════════════════════

  syncAvailableFieldSections() {
    const pool = this.availableSectionsTarget;

    // Remove existing field section items from pool
    pool.querySelectorAll('.tpl-form__section-item[data-section^="field:"]').forEach(el => el.remove());

    // Remove stale field section items from section order + tab zones
    const currentInstanceIds = new Set();
    this.element.querySelectorAll(".tpl-field-chip").forEach(chip => {
      const iid = chip.dataset.fieldInstanceId || chip.querySelector(".chip-input-instance-id")?.value;
      if (iid) currentInstanceIds.add(iid);
    });

    this.element.querySelectorAll('.tpl-form__section-item[data-section^="field:"]').forEach(el => {
      if (el.dataset.persist === "true") return; // skip pool items
      const iid = el.dataset.section.replace("field:", "");
      if (!currentInstanceIds.has(iid)) el.remove();
    });

    // Rebuild field section items in available pool
    const emptyMsg = pool.querySelector(".tpl-drop-zone__empty");
    this.element.querySelectorAll(".tpl-field-chip").forEach(chip => {
      const instanceId = chip.dataset.fieldInstanceId || chip.querySelector(".chip-input-instance-id")?.value;
      if (!instanceId) return;
      const label = chip.dataset.fieldLabel || chip.dataset.fieldName;
      const type = chip.dataset.fieldType;

      const item = document.createElement("div");
      item.className = "tpl-form__section-item tpl-form__section-item--field";
      item.draggable = true;
      item.dataset.section = `field:${instanceId}`;
      item.dataset.persist = "true";
      item.dataset.action = "dragstart->template-form#sectionDragStart dragend->template-form#sectionDragEnd";
      item.innerHTML = `
        <span class="tpl-form__drag-handle">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><circle cx="9" cy="5" r="2"/><circle cx="15" cy="5" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="9" cy="19" r="2"/><circle cx="15" cy="19" r="2"/></svg>
        </span>
        <span class="tpl-form__section-name">${this.esc(label)}</span>
        <span class="tpl-field-chip__type tpl-field-chip__type--${type}" style="font-size:0.6rem;">${type}</span>
      `;
      pool.insertBefore(item, emptyMsg);
    });

    this.reindexSectionOrder();
  }

  // ═══════════════════════════════════════════════════════════
  // DRAG & DROP (CHIPS BETWEEN ZONES)
  // ═══════════════════════════════════════════════════════════

  chipDragStart(event) {
    this._draggedChip = event.currentTarget;
    this._draggedChip.classList.add("dragging");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", "");
  }

  chipDragEnd() {
    if (this._draggedChip) {
      this._draggedChip.classList.remove("dragging");
      this._draggedChip = null;
    }
    this._clearAllDragOver();
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  _clearAllDragOver() {
    this.element.querySelectorAll(".drag-over").forEach(z => z.classList.remove("drag-over"));
  }

  // ═══════════════════════════════════════════════════════════
  // REINDEX ALL FIELDS
  // ═══════════════════════════════════════════════════════════

  reindexAllFields() {
    let idx = 0;
    this.element.querySelectorAll(".tpl-field-chip").forEach(chip => {
      const prefix = `template[field_definitions][${idx}]`;
      chip.querySelector(".chip-input-name").name = `${prefix}[name]`;
      chip.querySelector(".chip-input-label").name = `${prefix}[label]`;
      chip.querySelector(".chip-input-type").name = `${prefix}[type]`;
      chip.querySelector(".chip-input-default").name = `${prefix}[default_value]`;
      chip.querySelector(".chip-input-placeholder").name = `${prefix}[placeholder]`;
      chip.querySelector(".chip-input-required").name = `${prefix}[required]`;
      chip.querySelector(".chip-input-options").name = `${prefix}[options]`;
      chip.querySelector(".chip-input-tab").name = `${prefix}[tab]`;
      chip.querySelector(".chip-input-position").name = `${prefix}[position]`;
      chip.querySelector(".chip-input-position").value = idx;
      chip.querySelector(".chip-input-instance-id").name = `${prefix}[instance_id]`;
      idx++;
    });
  }
}
