import { Controller } from "@hotwired/stimulus"

const DESTRUCTIVE_WORDS = /\b(delete|discard|remove|revoke|reset|restore|archive|encrypt|reject|permanent)/i

export default class extends Controller {
  static targets = [
    "form", "eyebrow", "title", "message", "field", "input", "inputLabel",
    "cancelButton", "confirmButton"
  ]

  connect() {
    this._queue = []
    this._active = null
    this._installApi()
    this._installTurboConfirm()
  }

  disconnect() {
    if (this._active) this._settle(this._cancelValue())
    this._queue.splice(0).forEach(({ resolve, type }) => resolve(type === "confirm" ? false : type === "prompt" ? null : true))

    if (window.AppDialog === this._api) window.AppDialog = this._previousApi
    if (this._turboForms?.confirm === this._turboConfirm) {
      this._turboForms.confirm = this._previousTurboConfirm
    }
  }

  open(type, message, options = {}) {
    return new Promise((resolve) => {
      this._queue.push({ type, message: String(message ?? ""), options, resolve })
      this._presentNext()
    })
  }

  submit(event) {
    event.preventDefault()
    if (!this._active) return

    if (this._active.type === "prompt") {
      if (!this.formTarget.reportValidity()) return
      this._settle(this.inputTarget.value)
    } else {
      this._settle(true)
    }
  }

  cancel(event) {
    event?.preventDefault()
    this._settle(this._cancelValue())
  }

  backdropClose(event) {
    if (event.target === this.element) this.cancel(event)
  }

  closed() {
    if (this._active) this._settle(this._cancelValue(), { close: false })
  }

  _installApi() {
    this._previousApi = window.AppDialog
    this._api = {
      alert: (message, options = {}) => this.open("alert", message, options),
      confirm: (message, options = {}) => this.open("confirm", message, options),
      prompt: (message, options = {}) => this.open("prompt", message, options),
    }
    window.AppDialog = this._api
  }

  _installTurboConfirm() {
    this._turboForms = window.Turbo?.config?.forms
    if (!this._turboForms) return

    this._previousTurboConfirm = this._turboForms.confirm
    this._turboConfirm = (message, element, submitter) => {
      const destructive = this._isDestructive(message, element, submitter)
      return this._api.confirm(message, {
        title: destructive ? "Confirm change" : "Continue?",
        confirmLabel: destructive ? "Confirm" : "Continue",
        variant: destructive ? "danger" : "default",
      })
    }
    this._turboForms.confirm = this._turboConfirm
  }

  _presentNext() {
    if (this._active || this._queue.length === 0) return

    this._active = this._queue.shift()
    const { type, message, options } = this._active
    const destructive = options.variant === "danger" || this._isDestructive(message)

    this.element.dataset.variant = destructive ? "danger" : "default"
    this.eyebrowTarget.textContent = options.eyebrow || (destructive ? "Careful" : "Idea Foundry")
    this.titleTarget.textContent = options.title || this._defaultTitle(type, destructive)
    this.messageTarget.textContent = message
    this.confirmButtonTarget.textContent = options.confirmLabel || (type === "alert" ? "OK" : "Confirm")
    this.confirmButtonTarget.classList.toggle("btn-danger", destructive)
    this.confirmButtonTarget.classList.toggle("btn-primary", !destructive)
    this.cancelButtonTarget.hidden = type === "alert"

    const prompt = type === "prompt"
    this.fieldTarget.hidden = !prompt
    this.inputTarget.type = prompt ? "text" : "hidden"
    this.inputLabelTarget.textContent = options.inputLabel || "Value"
    this.inputTarget.value = options.defaultValue || ""
    this.inputTarget.placeholder = options.placeholder || ""
    this.inputTarget.required = Boolean(options.required)

    if (!this.element.open) this.element.showModal()
    requestAnimationFrame(() => {
      const focusTarget = prompt ? this.inputTarget : this.confirmButtonTarget
      focusTarget.focus()
      if (prompt) this.inputTarget.select()
    })
  }

  _settle(value, { close = true } = {}) {
    if (!this._active) return

    const { resolve } = this._active
    this._active = null
    this.inputTarget.type = "hidden"
    if (close && this.element.open) this.element.close()
    resolve(value)
    queueMicrotask(() => this._presentNext())
  }

  _cancelValue() {
    if (!this._active) return null
    return this._active.type === "confirm" ? false : this._active.type === "prompt" ? null : true
  }

  _defaultTitle(type, destructive) {
    if (type === "alert") return "Something needs attention"
    if (type === "prompt") return "Add details"
    return destructive ? "Confirm change" : "Continue?"
  }

  _isDestructive(message, element, submitter) {
    const method = submitter?.formMethod || element?.method || element?.dataset?.turboMethod || ""
    return method.toLowerCase() === "delete" || DESTRUCTIVE_WORDS.test(message || "")
  }
}
