import { Controller } from "@hotwired/stimulus"
import { DEFAULT_BINDINGS, binding, matches, sequenceKeys } from "lib/shortcut_bindings"

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

  stopPropagation(event) {
    event.stopPropagation()
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
    if (!event.key || event.isComposing) return

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

    this.handleSequence(event)
  }

  // Every non-sequence action fires on its effective binding (the user's, else the default).
  // Chord bindings (Ctrl/Cmd/Alt) work while typing; bare keys only outside fields and dialogs.
  handleComboShortcut(event) {
    if (event.altKey && /^\d$/.test(event.key.toLowerCase())) {
      const key = event.key.toLowerCase()
      event.preventDefault()
      this.switchTab(key === "0" ? 9 : Number(key) - 1)
      return true
    }

    const id = Object.keys(DEFAULT_BINDINGS).find((name) => matches(binding(name), event))
    const actions = id && this.shortcutActions()
    if (!actions?.[id]) return false

    const chord = /(Ctrl\/Cmd|Alt)\+/.test(binding(id))
    if (!chord && (this.constructor.isEditableTarget(event.target) || document.querySelector("dialog[open]"))) return false

    // A handler returning false found nothing to act on, so the key is left to the page.
    if (actions[id](event) === false) return false

    event.preventDefault()
    return true
  }

  shortcutActions() {
    const go = (url) => () => url && this.visit(url)
    const urls = this.navigationUrls()
    const actions = {
      cheatsheet: () => this.togglePanel(),
      hints: () => this.openHints(),
      focus_search: () => this.focusSearch(),
      save: (event) => this.saveCurrentContext(event.target),
      submit: (event) => this.submitCurrentContext(event.target),
      ask_agent: () => this.clickFirst("[data-shortcut-role~='ask-agent'], .ask-agent-launcher"),
      edit: () => this.clickFirst("[data-shortcut-role~='edit'], a[href$='/edit'], a[href*='/edit?']"),
      prev_tab: () => this.moveTab(-1),
      next_tab: () => this.moveTab(1),
    }
    Object.entries(urls).forEach(([id, url]) => { actions[id] = go(url) })
    return actions
  }

  navigationUrls() {
    return {
      go_plan: this.planUrlValue,
      go_ideas: this.ideasUrlValue,
      go_licensing: this.licensingUrlValue,
      go_intake: this.intakeUrlValue,
      go_topologies: this.topologiesUrlValue,
      go_kb: this.kbUrlValue,
      go_backlog: this.backlogUrlValue,
      go_settings: this.settingsUrlValue,
      new_idea: this.newIdeaUrlValue,
      new_list: this.newListUrlValue,
      new_topology: this.newTopologyUrlValue,
      new_import: this.importUrlValue,
    }
  }

  handleSequence(event) {
    if (this.constructor.isEditableTarget(event.target)) return
    if (document.querySelector("dialog[open]")) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    const key = event.key.toLowerCase()
    if (!/^[a-z0-9]$/.test(key)) return

    if (!this.sequence) {
      if (!Object.keys(DEFAULT_BINDINGS).some((id) => sequenceKeys(binding(id))?.[0] === key)) return

      event.preventDefault()
      this.sequence = key
      this.sequenceTimer = window.setTimeout(() => this.clearSequence(), 1500)
      return
    }

    event.preventDefault()
    const sequence = `${this.sequence} ${key}`
    this.clearSequence()
    this.executeSequence(sequence)
  }

  executeSequence(sequence) {
    const actions = this.shortcutActions()
    const id = Object.keys(actions).find((name) => binding(name)?.toLowerCase() === sequence)
    if (id) actions[id]({})
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
          ...["cheatsheet", "search", "hints", "focus_search", "save", "submit", "ask_agent"].map((id) => ({
            key: binding(id),
            label: id === "hints" ? `Show action hints for ${this.visibleActions.length} visible controls` : DEFAULT_BINDINGS[id].label,
          })),
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
    return Object.entries(this.navigationUrls())
      .filter(([, url]) => url)
      .map(([id]) => ({ key: binding(id), label: DEFAULT_BINDINGS[id].label }))
  }

  currentFlowShortcuts() {
    const items = []

    this.visibleTabs().slice(0, 9).forEach((tab, index) => {
      items.push({ key: `Alt+${index + 1}`, label: this.labelFor(tab) || `Tab ${index + 1}` })
    })

    if (this.visibleTabs().length > 1) {
      items.push({ key: binding("prev_tab"), label: "Previous tab" })
      items.push({ key: binding("next_tab"), label: "Next tab" })
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

    if (!search) return false

    search.focus()
    search.select?.()
    return true
  }

  // The focused form, else the first form in <main>. Never a data-shortcut-skip form: lock forms must not be saved or submitted by shortcut.
  actionForm(target) {
    const own = target?.closest?.("form")
    if (own && !own.closest("[data-shortcut-skip]")) return own

    return this.firstVisible("main form:not([data-shortcut-skip])")
  }

  saveCurrentContext(target) {
    const form = this.actionForm(target)
    // Unfocused forms only save via an explicit role or primary button, never an arbitrary submit (Delete).
    const focused = form && form === target?.closest?.("form")
    const saveControl = form?.querySelector(focused
      ? "[data-shortcut-role~='save'], button[type='submit'], input[type='submit']"
      : "[data-shortcut-role~='save'], button[type='submit'].btn-primary, input[type='submit'].btn-primary")
    if (saveControl) {
      saveControl.click()
      return
    }

    this.clickFirst("[data-shortcut-role~='save']:not([data-shortcut-skip] *), main button[type='submit'].btn-primary:not([data-shortcut-skip] *), main input[type='submit'].btn-primary:not([data-shortcut-skip] *)")
  }

  submitCurrentContext(target) {
    const form = this.actionForm(target)
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
    if (tabs.length === 0) return false

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
