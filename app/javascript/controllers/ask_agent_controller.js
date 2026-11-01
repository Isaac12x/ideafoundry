import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "body", "invention", "launcher", "messages", "panel"]
  static inventionVariants = ["bulb", "engine", "magnet", "gyro"]
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

  // "ask-agent:queued" { question }: a question was sent without a page load (KB "Expand"); show it as pending.
  // The panel opens without taking focus, so the reader's selection and scroll position stay put.
  queued({ question }) {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.querySelector(".ask-agent-sidebar__empty")?.remove()
    const article = document.createElement("article")
    article.className = "ask-agent-thread"
    article.innerHTML = `<div class="ask-agent-message ask-agent-message--user"><div class="ask-agent-message__meta"><span>You</span><time>just now</time></div><p></p></div>
      <div class="ask-agent-message ask-agent-message--pending"><div class="ask-agent-message__meta"><span>Agent</span><time>Pending</time></div><p>Waiting for an answer.</p></div>`
    article.querySelector("p").textContent = question
    this.messagesTarget.appendChild(article)
    this.open(null, { focus: false })
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
