import { Controller } from "@hotwired/stimulus"

const HINT_CHARS = "asdfghjklqwertyuiopzxcvbnm1234567890"

export default class extends Controller {
  static targets = ["flow", "hintLayer", "panel", "sections", "toggle"]
  static values = {
    planUrl: String,
    ideasUrl: String,
    licensingUrl: String,
    intakeUrl: String,
    topologiesUrl: String,
    kbUrl: String,
    backlogUrl: String,
    settingsUrl: String,
    newIdeaUrl: String,
    newListUrl: String,
    newTopologyUrl: String,
    importUrl: String,
  }

  static hintForIndex(index) {
    if (index < HINT_CHARS.length) return HINT_CHARS[index]

    const base = HINT_CHARS.length
    const first = Math.floor(index / base) - 1
    const second = index % base

    return `${HINT_CHARS[first % base]}${HINT_CHARS[second]}`
  }

  static isEditableTarget(target) {
    if (!target || !(target instanceof Element)) return false
    if (target.closest("[contenteditable='true']")) return true
    if (target.closest(".ProseMirror")) return true
    if (target instanceof HTMLTextAreaElement) return true
    if (target instanceof HTMLSelectElement) return true
    if (!(target instanceof HTMLInputElement)) return false

    return !["button", "checkbox", "color", "file", "hidden", "radio", "range", "reset", "submit"].includes(target.type)
  }

  connect() {
    this.sequence = null
    this.sequenceTimer = null
    this.hintMode = false
    this.hintBuffer = ""
    this.visibleActions = []
    this.rendering = false

    this.boundKeydown = this.onKeydown.bind(this)
    this.boundRefresh = this.scheduleRefresh.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    document.addEventListener("turbo:load", this.boundRefresh)
    document.addEventListener("turbo:frame-render", this.boundRefresh)
    document.addEventListener("turbo:render", this.boundRefresh)

    this.observer = new MutationObserver((mutations) => this.handleMutations(mutations))
    this.observer.observe(document.body, {
      attributes: true,
      attributeFilter: ["aria-hidden", "class", "hidden", "style"],
      childList: true,
      subtree: true,
    })

    this.refresh()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener("turbo:load", this.boundRefresh)
    document.removeEventListener("turbo:frame-render", this.boundRefresh)
    document.removeEventListener("turbo:render", this.boundRefresh)
    this.observer?.disconnect()
    this.clearSequence()
    this.closeHints()
    window.clearTimeout(this.refreshTimer)
  }

  togglePanel(event) {
    event?.preventDefault()
    this.panelOpen() ? this.closePanel() : this.openPanel()
  }

  openPanel() {
    if (!this.hasPanelTarget) return

    this.refresh()
    this.panelTarget.hidden = false
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  closePanel() {
    if (!this.hasPanelTarget) return

    this.panelTarget.hidden = true
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
  }

  onKeydown(event) {
    if (this.hintMode) {
      this.handleHintKey(event)
      return
    }

    if (event.key === "Escape" && this.panelOpen()) {
      event.preventDefault()
      this.closePanel()
      return
    }

    if (this.handleComboShortcut(event)) return

    if (this.constructor.isEditableTarget(event.target)) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "?") {
      event.preventDefault()
      this.togglePanel()
      return
    }

    if (event.key === "/") {
      event.preventDefault()
      this.focusSearch()
      return
    }

    if (event.key === "]" || event.key === "[") {
      event.preventDefault()
      this.moveTab(event.key === "]" ? 1 : -1)
      return
    }

    if (event.key.toLowerCase() === "e") {
      this.clickFirst("[data-shortcut-role~='edit'], a[href$='/edit'], a[href*='/edit?']")
      return
    }

    this.handleSequence(event)
  }

  handleComboShortcut(event) {
    const key = event.key.toLowerCase()
    const mod = event.metaKey || event.ctrlKey

    if (mod && event.shiftKey && key === "l") return false

    if (mod && key === ".") {
      event.preventDefault()
      this.openHints()
      return true
    }

    if (mod && key === "j") {
      event.preventDefault()
      this.clickFirst("[data-shortcut-role~='ask-agent'], .ask-agent-launcher")
      return true
    }

    if (mod && key === "s") {
      event.preventDefault()
      this.saveCurrentContext(event.target)
      return true
    }

    if (mod && key === "enter") {
      event.preventDefault()
      this.submitCurrentContext(event.target)
      return true
    }

    if (event.altKey && /^\d$/.test(key)) {
      const index = key === "0" ? 9 : Number(key) - 1
      event.preventDefault()
      this.switchTab(index)
      return true
    }

    return false
  }

  handleSequence(event) {
    const key = event.key.toLowerCase()
    if (!/^[a-z]$/.test(key)) return

    if (!this.sequence && (key === "g" || key === "n")) {
      event.preventDefault()
      this.sequence = key
      this.sequenceTimer = window.setTimeout(() => this.clearSequence(), 1500)
      return
    }

    if (!this.sequence) return

    event.preventDefault()
    const sequence = `${this.sequence} ${key}`
    this.clearSequence()
    this.executeSequence(sequence)
  }

  executeSequence(sequence) {
    const routes = {
      "g p": this.planUrlValue,
      "g i": this.ideasUrlValue,
      "g l": this.licensingUrlValue,
      "g n": this.intakeUrlValue,
      "g t": this.topologiesUrlValue,
      "g k": this.kbUrlValue,
      "g b": this.backlogUrlValue,
      "g s": this.settingsUrlValue,
      "n i": this.newIdeaUrlValue,
      "n l": this.newListUrlValue,
      "n t": this.newTopologyUrlValue,
      "n s": this.importUrlValue,
    }

    const url = routes[sequence]
    if (url) this.visit(url)
  }

  clearSequence() {
    window.clearTimeout(this.sequenceTimer)
    this.sequence = null
    this.sequenceTimer = null
  }

  refresh() {
    if (this.rendering) return

    this.visibleActions = this.collectVisibleActions()
    this.renderPanel()
  }

  scheduleRefresh() {
    window.clearTimeout(this.refreshTimer)
    this.refreshTimer = window.setTimeout(() => this.refresh(), 60)
  }

  handleMutations(mutations) {
    if (this.rendering) return

    const onlyOwnUi = mutations.every((mutation) => {
      const target = mutation.target
      return target instanceof Element && Boolean(target.closest(".shortcuts-shell, .shortcut-hint-layer"))
    })
    if (onlyOwnUi) return

    this.scheduleRefresh()
  }

  renderPanel() {
    if (!this.hasSectionsTarget) return

    const flowName = this.currentFlowName()
    if (this.hasFlowTarget) this.flowTarget.textContent = flowName

    const sections = this.cheatsheetSections()
    this.rendering = true
    this.sectionsTarget.replaceChildren(...sections.map((section) => this.renderSection(section)))
    this.rendering = false
  }

  renderSection(section) {
    const wrapper = document.createElement("section")
    wrapper.className = "shortcuts-section"

    const heading = document.createElement("h3")
    heading.textContent = section.title
    wrapper.appendChild(heading)

    const list = document.createElement("dl")
    list.className = "shortcuts-list"

    section.items.forEach((item) => {
      const row = document.createElement("div")
      row.className = "shortcuts-list__row"

      const dt = document.createElement("dt")
      dt.appendChild(this.renderKey(item.key))

      const dd = document.createElement("dd")
      dd.textContent = item.label

      row.append(dt, dd)
      list.appendChild(row)
    })

    wrapper.appendChild(list)
    return wrapper
  }

  renderKey(key) {
    const fragment = document.createDocumentFragment()
    String(key).split(" ").forEach((part, index) => {
      if (index > 0) {
        const spacer = document.createElement("span")
        spacer.className = "shortcuts-key-space"
        spacer.textContent = "then"
        fragment.appendChild(spacer)
      }

      const kbd = document.createElement("kbd")
      kbd.textContent = part
      fragment.appendChild(kbd)
    })

    return fragment
  }

  cheatsheetSections() {
    const sections = [
      {
        title: "Global",
        items: [
          { key: "?", label: "Toggle this cheatsheet" },
          { key: "Ctrl/Cmd+K", label: "Search ideas" },
          { key: "Ctrl/Cmd+.", label: `Show action hints for ${this.visibleActions.length} visible controls` },
          { key: "/", label: "Focus search or filters" },
          { key: "Ctrl/Cmd+S", label: "Save the current form" },
          { key: "Ctrl/Cmd+Enter", label: "Submit the current form" },
          { key: "Ctrl/Cmd+J", label: "Open Ask Agent" },
        ],
      },
      {
        title: "Navigation",
        items: this.navigationShortcuts(),
      },
    ]

    const flowItems = this.currentFlowShortcuts()
    if (flowItems.length > 0) {
      sections.push({ title: "Current Flow", items: flowItems })
    }

    return sections
  }

  navigationShortcuts() {
    const shortcuts = [
      ["g p", "Plan", this.planUrlValue],
      ["g i", "Ideas", this.ideasUrlValue],
      ["g l", "Licensing", this.licensingUrlValue],
      ["g n", "Intake", this.intakeUrlValue],
      ["g t", "Topologies", this.topologiesUrlValue],
      ["g k", "Knowledge Base", this.kbUrlValue],
      ["g b", "Backlog", this.backlogUrlValue],
      ["g s", "Settings", this.settingsUrlValue],
      ["n i", "New idea", this.newIdeaUrlValue],
      ["n l", "New named list", this.newListUrlValue],
      ["n t", "New topology", this.newTopologyUrlValue],
      ["n s", "Import submissions", this.importUrlValue],
    ]

    return shortcuts
      .filter(([, , url]) => url)
      .map(([key, label]) => ({ key, label }))
  }

  currentFlowShortcuts() {
    const items = []

    this.visibleTabs().slice(0, 9).forEach((tab, index) => {
      items.push({ key: `Alt+${index + 1}`, label: this.labelFor(tab) || `Tab ${index + 1}` })
    })

    if (this.visibleTabs().length > 1) {
      items.push({ key: "[", label: "Previous tab" })
      items.push({ key: "]", label: "Next tab" })
    }

    const explicit = this.explicitShortcuts()
    explicit.forEach((item) => items.push(item))

    this.visibleActions.filter((action) => !action.element.closest(".app-header")).slice(0, 12).forEach((action) => {
      items.push({ key: action.hint.toUpperCase(), label: action.label })
    })

    return this.uniqueItems(items).slice(0, 24)
  }

  explicitShortcuts() {
    return Array.from(document.querySelectorAll("[data-shortcut-key]"))
      .filter((element) => this.isVisible(element))
      .filter((element) => !element.closest(".app-header, .shortcuts-shell, .command-palette"))
      .map((element) => ({
        key: element.dataset.shortcutKey,
        label: element.dataset.shortcutLabel || this.labelFor(element),
      }))
      .filter((item) => item.key && item.label)
  }

  uniqueItems(items) {
    const seen = new Set()
    return items.filter((item) => {
      const signature = `${item.key}:${item.label}`
      if (seen.has(signature)) return false
      seen.add(signature)
      return true
    })
  }

  collectVisibleActions() {
    const selector = [
      "a[href]",
      "button:not([disabled])",
      "input:not([type='hidden']):not([disabled])",
      "select:not([disabled])",
      "textarea:not([disabled])",
      "[role='button']",
      "[tabindex]:not([tabindex='-1'])",
    ].join(",")

    return Array.from(document.querySelectorAll(selector))
      .filter((element) => this.actionEligible(element))
      .map((element, index) => ({
        element,
        hint: this.constructor.hintForIndex(index),
        label: this.labelFor(element) || `Action ${index + 1}`,
      }))
  }

  actionEligible(element) {
    if (!this.isVisible(element)) return false
    if (element.closest(".shortcuts-shell, .shortcut-hint-layer, .command-palette")) return false
    if (element.closest("template")) return false
    if (element.matches("[aria-disabled='true'], [data-shortcut-skip]")) return false

    return true
  }

  openHints() {
    if (!this.hasHintLayerTarget) return

    this.refresh()
    this.hintMode = true
    this.hintBuffer = ""
    document.body.classList.add("shortcuts-hints-active")
    this.hintLayerTarget.hidden = false
    this.hintLayerTarget.replaceChildren(...this.visibleActions.map((action) => this.renderHint(action)))
  }

  closeHints() {
    this.hintMode = false
    this.hintBuffer = ""
    document.body.classList.remove("shortcuts-hints-active")
    if (this.hasHintLayerTarget) {
      this.hintLayerTarget.hidden = true
      this.hintLayerTarget.replaceChildren()
    }
  }

  renderHint(action) {
    const rect = action.element.getBoundingClientRect()
    const hint = document.createElement("span")
    hint.className = "shortcut-hint"
    hint.textContent = action.hint.toUpperCase()
    hint.style.left = `${Math.max(6, rect.left + 4)}px`
    hint.style.top = `${Math.max(6, rect.top + 4)}px`
    return hint
  }

  handleHintKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeHints()
      return
    }

    if (event.key === "Backspace") {
      event.preventDefault()
      this.hintBuffer = this.hintBuffer.slice(0, -1)
      this.updateHintVisibility()
      return
    }

    const key = event.key.toLowerCase()
    if (!HINT_CHARS.includes(key)) return

    event.preventDefault()
    this.hintBuffer += key

    const matches = this.visibleActions.filter((action) => action.hint.startsWith(this.hintBuffer))
    const exact = matches.find((action) => action.hint === this.hintBuffer)
    if (exact) {
      this.activateHint(exact)
    } else if (matches.length === 0) {
      this.hintBuffer = key
      this.updateHintVisibility()
    } else {
      this.updateHintVisibility()
    }
  }

  updateHintVisibility() {
    if (!this.hasHintLayerTarget) return

    const hints = Array.from(this.hintLayerTarget.querySelectorAll(".shortcut-hint"))
    hints.forEach((hint, index) => {
      const action = this.visibleActions[index]
      hint.classList.toggle("is-muted", this.hintBuffer && !action.hint.startsWith(this.hintBuffer))
    })
  }

  activateHint(action) {
    const element = action.element
    this.closeHints()
    element.scrollIntoView?.({ block: "center", inline: "center" })

    if (this.focusOnly(element)) {
      element.focus()
      element.select?.()
      return
    }

    element.click()
  }

  focusOnly(element) {
    return element instanceof HTMLInputElement ||
      element instanceof HTMLTextAreaElement ||
      element instanceof HTMLSelectElement ||
      element.isContentEditable
  }

  focusSearch() {
    const search = this.firstVisible([
      "[data-shortcut-role~='search']",
      "input[type='search']",
      "input[name='search']",
      "input[name='q']",
      "input[placeholder*='Search' i]",
      "input[aria-label*='Search' i]",
      ".topology-graph-search",
    ].join(","))

    if (search) {
      search.focus()
      search.select?.()
    }
  }

  saveCurrentContext(target) {
    const form = target?.closest?.("form") || this.firstVisible("form")
    const saveControl = form?.querySelector("[data-shortcut-role~='save'], button[type='submit'], input[type='submit']")
    if (saveControl) {
      saveControl.click()
      return
    }

    this.clickFirst("[data-shortcut-role~='save'], button[type='submit'].btn-primary, input[type='submit'].btn-primary")
  }

  submitCurrentContext(target) {
    const form = target?.closest?.("form") || this.firstVisible("form")
    if (!form) return

    if (form.requestSubmit) {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  switchTab(index) {
    const tabs = this.visibleTabs()
    tabs[index]?.click()
    this.scheduleRefresh()
  }

  moveTab(delta) {
    const tabs = this.visibleTabs()
    if (tabs.length === 0) return

    const current = tabs.findIndex((tab) => tab.classList.contains("active") || tab.getAttribute("aria-selected") === "true")
    const next = ((current >= 0 ? current : 0) + delta + tabs.length) % tabs.length
    tabs[next].click()
    this.scheduleRefresh()
  }

  visibleTabs() {
    return Array.from(document.querySelectorAll("[data-tabs-target~='tab'], .tab-button[data-tab-name], .view-toggle__btn[data-tab-name]"))
      .filter((tab) => this.isVisible(tab))
  }

  clickFirst(selector) {
    const element = this.firstVisible(selector)
    if (!element) return false

    element.click()
    return true
  }

  firstVisible(selector) {
    return Array.from(document.querySelectorAll(selector)).find((element) => this.isVisible(element))
  }

  labelFor(element) {
    const label = element.dataset.shortcutLabel ||
      element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      element.getAttribute("placeholder") ||
      element.value ||
      element.textContent ||
      element.name ||
      element.id

    return this.cleanLabel(label)
  }

  cleanLabel(label) {
    return String(label || "")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 80)
  }

  isVisible(element) {
    if (!(element instanceof Element)) return false
    if (element.hidden || element.closest("[hidden], [aria-hidden='true']")) return false

    const style = window.getComputedStyle(element)
    if (style.display === "none" || style.visibility === "hidden") return false

    const rect = element.getBoundingClientRect()
    return rect.width > 0 && rect.height > 0
  }

  panelOpen() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  currentFlowName() {
    const title = this.cleanLabel(
      document.querySelector("main h1, main h2, .page-header h2, .page-header h1")?.textContent ||
      document.title ||
      "Current flow"
    )
    const activeTab = this.cleanLabel(this.visibleTabs().find((tab) => tab.classList.contains("active"))?.textContent)

    return activeTab ? `${title} / ${activeTab}` : title
  }

  visit(url) {
    if (typeof Turbo !== "undefined") {
      Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }
}
