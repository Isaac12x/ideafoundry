import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "body", "launcher", "messages", "panel"]

  connect() {
    this.resizing = false

    if (this.shouldOpenFromUrl()) {
      requestAnimationFrame(() => {
        this.open()
        this.clearOpenParam()
      })
    }
  }

  disconnect() {
    this.stopResize()
  }

  open(event) {
    event?.preventDefault()
    if (!this.hasPanelTarget) return

    this.panelTarget.hidden = false
    if (this.hasBackdropTarget) {
      this.backdropTarget.hidden = false
    }
    if (this.hasLauncherTarget) {
      this.launcherTarget.setAttribute("aria-expanded", "true")
    }
    document.body.classList.add("ask-agent-open")
    this.scrollMessages()

    if (this.hasBodyTarget) {
      this.bodyTarget.focus()
    }
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
}
