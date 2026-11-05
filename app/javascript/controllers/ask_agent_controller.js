import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "body", "error", "invention", "launcher", "messages", "panel", "status"]
  static values = { questionsUrl: String }
  static inventionVariants = ["bulb", "engine", "magnet", "gyro"]
  static errors = { disabled: "The local agent is turned off.", blank: "Enter a question." }
  static inventionStorageKey = "idea-foundry:ask-agent:invention"

  connect() {
    if (document.body.classList.contains("typing-lock-page")) {
      this.element.hidden = true
      this.element.setAttribute("aria-hidden", "true")
      return
    }

    this.resizing = false
    this.onPrefill = ({ detail }) => this.prefill(detail)
    this.onQueued = ({ detail }) => this.queued(detail)
    window.addEventListener("ask-agent:prefill", this.onPrefill)
    window.addEventListener("ask-agent:queued", this.onQueued)
    this.onVisibility = () => (document.visibilityState === "visible" ? this.refresh() : this.stopPolling())
    document.addEventListener("visibilitychange", this.onVisibility)
    this.seq = 0
    this.gone = false
    this.markChange()
    this.schedule() // a question asked just before a reload is still pending
    this.inventionIndex = this.initialInventionIndex()
    this.showCurrentInvention({ immediate: true })
    this.startInventionCycle()

    if (this.shouldOpenFromUrl()) {
      requestAnimationFrame(() => {
        this.open()
        this.clearOpenParam()
      })
    }
  }

  disconnect() {
    window.removeEventListener("ask-agent:prefill", this.onPrefill)
    window.removeEventListener("ask-agent:queued", this.onQueued)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.gone = true
    this.stopPolling()
    this.stopResize()
    this.stopInventionCycle()
    window.clearTimeout(this.swapTimer)
  }

  open(event, { focus = true } = {}) {
    event?.preventDefault()
    if (!this.hasPanelTarget) return

    if (!this.isOpen()) this.trigger = document.activeElement
    this.panelTarget.hidden = false
    if (this.hasBackdropTarget) {
      this.backdropTarget.hidden = false
    }
    if (this.hasLauncherTarget) {
      this.launcherTarget.setAttribute("aria-expanded", "true")
    }
    document.body.classList.add("ask-agent-open")
    this.clearUnread()
    this.scrollMessages()

    if (focus && this.hasBodyTarget) {
      this.bodyTarget.focus()
    }
  }

  // "ask-agent:prefill" { text }: open with text in the question box, cursor at the end (KB "Ask AI").
  prefill({ text }) {
    if (!this.hasBodyTarget) return
    this.bodyTarget.value = text
    this.open()
    this.bodyTarget.setSelectionRange(text.length, text.length)
  }

  // "ask-agent:queued": a question was sent without a page load (KB "Expand"); fetch the threads so it shows as pending.
  // The panel opens without taking focus, so the reader's selection and scroll position stay put.
  queued() {
    this.markChange()
    this.open(null, { focus: false })
    return this.refresh({ scroll: true })
  }

  // Sidebar form: post by fetch (the plain form post stays as the no-JS fallback), then show the new thread.
  async send(event) {
    event.preventDefault()
    const form = event.currentTarget
    const button = form.querySelector("[type=submit]")
    if (button.disabled) return
    this.markChange()
    button.disabled = true
    this.showError("")
    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form), credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      const result = response.redirected ? {} : await response.json().catch(() => ({}))
      if (!response.ok || response.redirected) throw new Error(this.constructor.errors[result.error] || "The question was not sent.")
      this.halted = false
      this.bodyTarget.value = ""
      this.bodyTarget.focus()
      await this.refresh({ scroll: true })
    } catch (error) {
      this.showError(error instanceof TypeError ? "Could not reach the server. Your question is still here; try again." : error.message)
    } finally {
      button.disabled = false
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = !message
  }

  // ponytail: fixed 3s poll, only while a question is pending and the tab is visible; no backoff. Ceiling: one small
  // query per 3s per open tab. Upgrade to ActionCable once cable.yml is not `async` and the cable connection checks the session.
  schedule() {
    this.stopPolling()
    if (this.gone || this.halted || document.visibilityState !== "visible" || !(this.pending() || this.deferred)) return
    // A question that stays unanswered is never given up on (a late answer must appear), but it backs off to 30s after 2 minutes.
    const idle = Date.now() - this.changedAt > 120000
    this.pollTimer = window.setTimeout(() => this.refresh(), idle ? 30000 : 3000)
  }

  markChange() {
    this.changedAt = Date.now()
    this.pendingCount = this.countPending(this.hasMessagesTarget ? this.messagesTarget.innerHTML : "")
  }

  countPending(html) {
    return (html.match(/ask-agent-message--pending/g) || []).length
  }

  clearUnread() {
    if (!this.hasLauncherTarget) return
    delete this.launcherTarget.dataset.unread
    this.launcherTarget.setAttribute("aria-label", "Open Ask Agent")
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }

  stopPolling() {
    window.clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  pending() {
    return this.hasMessagesTarget && !!this.messagesTarget.querySelector(".ask-agent-message--pending")
  }

  // Locked (cover up) or hidden: no answer text may reach the DOM.
  locked() {
    return !!document.getElementById("typing-lock-cover") || this.element.hidden
  }

  async refresh({ scroll = false } = {}) {
    if (this.gone || !this.hasMessagesTarget || this.locked() || (this.halted && !scroll)) return
    if (!this.pending() && !this.deferred && !scroll) return this.schedule()
    const id = ++this.seq
    try {
      const response = await fetch(this.questionsUrlValue, { credentials: "same-origin", cache: "no-store", headers: { Accept: "text/html" } })
      // A redirect (lock/login page), 401 or 403 means the session is gone or the agent is off: stop, and never inject that page.
      if (response.redirected || response.status === 401 || response.status === 403) return (this.halted = true)
      if (!response.ok) return
      const html = await response.text()
      if (id === this.seq && !this.locked()) this.render(html, scroll)
    } catch (_error) {
      // Network failure: keep what is shown; the next tick retries.
    } finally {
      if (id === this.seq) this.schedule()
    }
  }

  // Touch the DOM only when the markup changed beyond the relative-time labels, and never under a selection in the messages
  // (retried next tick via `deferred`). Stay put unless the reader was at the bottom.
  render(html, scroll) {
    const next = document.createElement("div")
    next.innerHTML = html
    const box = this.messagesTarget
    const bare = (markup) => markup.replace(/<time>.*?<\/time>/g, "")
    if (bare(next.innerHTML) === bare(box.innerHTML)) return (this.deferred = false)
    const selection = document.getSelection?.()
    if (selection && !selection.isCollapsed && box.contains(selection.anchorNode)) return (this.deferred = true)
    this.deferred = false
    const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 80
    const before = this.pendingCount
    box.replaceChildren(...next.childNodes)
    this.pendingCount = this.countPending(box.innerHTML)
    if (this.pendingCount !== before) this.changedAt = Date.now()
    if (this.pendingCount < before && !this.isOpen()) this.markUnread()
    if (scroll || atBottom) this.scrollMessages()
  }

  // Answer landed while the panel is closed: dot on the launcher plus a polite announcement; the panel is never opened for the reader.
  markUnread() {
    if (this.hasLauncherTarget) {
      this.launcherTarget.dataset.unread = ""
      this.launcherTarget.setAttribute("aria-label", "Open Ask Agent (new answer)")
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = "Ask Agent has a new answer."
  }

  close() {
    if (!this.hasPanelTarget) return

    this.panelTarget.hidden = true
    if (this.hasBackdropTarget) {
      this.backdropTarget.hidden = true
    }
    if (this.hasLauncherTarget) {
      this.launcherTarget.setAttribute("aria-expanded", "false")
    }
    document.body.classList.remove("ask-agent-open")
    this.stopResize()
    if (this.trigger?.isConnected) this.trigger.focus?.({ preventScroll: true })
    this.trigger = null
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && this.isOpen()) {
      this.close()
    }
  }

  startResize(event) {
    if (!this.hasPanelTarget) return
    if (event.button !== undefined && event.button !== 0) return

    this.resizing = true
    event.preventDefault()
    event.currentTarget.setPointerCapture?.(event.pointerId)
    document.body.classList.add("ask-agent-resizing")
    this.resize(event)
  }

  resize(event) {
    if (!this.resizing) return

    this.setPanelWidth(window.innerWidth - event.clientX)
  }

  resizeWithKeyboard(event) {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return
    if (!this.hasPanelTarget) return

    event.preventDefault()
    const currentWidth = this.panelTarget.getBoundingClientRect().width
    const delta = event.key === "ArrowLeft" ? 40 : -40
    this.setPanelWidth(currentWidth + delta)
  }

  stopResize() {
    if (!this.resizing) return

    this.resizing = false
    document.body.classList.remove("ask-agent-resizing")
  }

  setPanelWidth(width) {
    const viewportWidth = window.innerWidth
    const minimumWidth = Math.min(360, viewportWidth - 16)
    const maximumWidth = Math.max(minimumWidth, viewportWidth - 24)
    const clampedWidth = Math.min(Math.max(width, minimumWidth), maximumWidth)

    this.panelTarget.style.width = `${clampedWidth}px`
  }

  scrollMessages() {
    if (!this.hasMessagesTarget) return

    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  isOpen() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  shouldOpenFromUrl() {
    return new URLSearchParams(window.location.search).get("ask_agent") === "open"
  }

  clearOpenParam() {
    const url = new URL(window.location.href)
    url.searchParams.delete("ask_agent")
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`)
  }

  startInventionCycle() {
    if (!this.hasLauncherTarget || !this.hasInventionTarget) return

    this.inventionTimer = window.setTimeout(() => {
      this.inventionIndex = this.initialInventionIndex()
      this.showCurrentInvention()
      this.startInventionCycle()
    }, this.millisecondsUntilNextInventionDay())
  }

  stopInventionCycle() {
    if (!this.inventionTimer) return

    window.clearTimeout(this.inventionTimer)
    this.inventionTimer = null
  }

  showCurrentInvention({ immediate = false } = {}) {
    if (!this.hasLauncherTarget || !this.hasInventionTarget) return

    const invention = this.constructor.inventionVariants[this.inventionIndex]
    this.launcherTarget.dataset.invention = invention

    if (this.inventionTarget.dataset.currentInvention === invention) return

    const template = this.element.querySelector(`template[data-ask-agent-invention-template="${invention}"]`)
    if (!template) return

    if (immediate || this.prefersReducedMotion()) {
      this.replaceInvention(template, invention)
      return
    }

    this.inventionTarget.classList.add("is-swapping")
    window.clearTimeout(this.swapTimer)
    this.swapTimer = window.setTimeout(() => {
      if (this.hasInventionTarget) this.replaceInvention(template, invention)
    }, 180)
  }

  replaceInvention(template, invention) {
    this.inventionTarget.replaceChildren(template.content.cloneNode(true))
    this.inventionTarget.dataset.currentInvention = invention
    this.inventionTarget.classList.remove("is-swapping")
  }

  initialInventionIndex() {
    const invention = this.dailyInvention()
    const index = this.constructor.inventionVariants.indexOf(invention)
    return index >= 0 ? index : 0
  }

  dailyInvention() {
    const day = this.currentInventionDay()
    const stored = this.storedInvention()

    if (stored?.day === day && this.validInvention(stored.invention)) {
      return stored.invention
    }

    const invention = this.pickDailyInvention(day, stored?.invention)
    this.storeInvention({ day, invention })
    return invention
  }

  pickDailyInvention(day, previousInvention) {
    const variants = this.constructor.inventionVariants
    if (variants.length === 0) return null

    let index = this.hashString(day) % variants.length
    if (variants.length > 1 && variants[index] === previousInvention) {
      index = (index + 1) % variants.length
    }

    return variants[index]
  }

  currentInventionDay(now = new Date()) {
    const year = now.getFullYear()
    const month = String(now.getMonth() + 1).padStart(2, "0")
    const day = String(now.getDate()).padStart(2, "0")

    return `${year}-${month}-${day}`
  }

  millisecondsUntilNextInventionDay(now = new Date()) {
    const nextDay = new Date(now)
    nextDay.setHours(24, 0, 0, 0)

    return Math.max(nextDay.getTime() - now.getTime(), 60000)
  }

  storedInvention() {
    try {
      const raw = window.localStorage?.getItem(this.constructor.inventionStorageKey)
      return raw ? JSON.parse(raw) : null
    } catch (_error) {
      return null
    }
  }

  storeInvention(record) {
    try {
      window.localStorage?.setItem(this.constructor.inventionStorageKey, JSON.stringify(record))
    } catch (_error) {
      // Ignore unavailable storage; the date hash still keeps a stable daily icon.
    }
  }

  validInvention(invention) {
    return this.constructor.inventionVariants.includes(invention)
  }

  hashString(value) {
    return Array.from(value).reduce((hash, char) => {
      return ((hash << 5) - hash + char.charCodeAt(0)) >>> 0
    }, 0)
  }

  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
