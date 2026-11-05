import { Controller } from "@hotwired/stimulus"
import { clampMenu, fieldSelection, nextIndex, quoteAfterSelection, selectionPrompt } from "lib/kb_selection_menu"

// Right-click on selected text in a KB markdown file (rendered article or the edit textarea) swaps the browser
// menu for the app's: Add, Expand, Ask AI, Copy. No selection -> the native menu stays.
//   Add     rendered: highlight the selection (kb-annotate on the same element); editor: quote it below.
//   Expand  queues the "expand this" question with the local agent (same endpoint as the Ask Agent form, by fetch:
//           no reload, scroll and selection stay) and shows it pending in the Ask Agent panel.
//   Ask AI  opens Ask Agent with the quoted selection, cursor ready for the question.
//   Agent off (no Ask Agent shell, or the agent is disabled): the items stay, and say so with a link to Settings.
// Styling reuses .idea-context-menu.
export default class extends Controller {
  static values = { file: String, questionsUrl: String, settingsUrl: String }

  connect() {
    this.onKey = (event) => this.key(event)
    this.onAway = (event) => { if (this.menu && !this.menu.contains(event.target)) this.close() }
    this.onScroll = (event) => { if (!this.menu?.contains(event.target)) this.close() }
    this.onBlur = () => this.close(false)
    this.element.addEventListener("contextmenu", (event) => this.open(event))
  }

  disconnect() {
    this.close(false)
  }

  open(event) {
    const field = event.target.closest?.("textarea")
    const article = event.target.closest?.(".kb-markdown")
    let text = ""
    if (field) text = fieldSelection(field)
    else if (article) {
      const sel = window.getSelection()
      const inside = sel?.rangeCount && sel.getRangeAt(0)
      if (inside && !inside.collapsed && article.contains(inside.startContainer) && article.contains(inside.endContainer)) text = sel.toString()
    }
    if (!text.trim()) return // native menu

    event.preventDefault()
    this.application.getControllerForElementAndIdentifier(this.element, "kb-annotate")?.hide() // one floating UI at a time
    this.close(false)
    this.text = text
    this.field = field
    this.opener = document.activeElement
    this.build(Boolean(field))
    document.body.appendChild(this.menu)
    const { width, height } = this.menu.getBoundingClientRect()
    const { left, top } = clampMenu(event.clientX, event.clientY, width, height, window.innerWidth, window.innerHeight, 12)
    Object.assign(this.menu.style, { left: `${left}px`, top: `${top}px` })
    this.items()[0]?.focus({ preventScroll: true })
    document.addEventListener("keydown", this.onKey, true)
    document.addEventListener("pointerdown", this.onAway, true)
    window.addEventListener("scroll", this.onScroll, true)
    window.addEventListener("blur", this.onBlur)
  }

  build(editing) {
    const entries = [
      [editing ? "Add as quote" : "Add highlight", () => this.add()],
      ["Expand", () => this.expand()],
      ["Ask AI", () => this.ask()],
      ["Copy", () => this.copy()]
    ]
    this.menu = Object.assign(document.createElement("div"), { className: "idea-context-menu kb-selection-menu" })
    this.menu.setAttribute("role", "menu")
    this.menu.setAttribute("aria-label", "Selection")
    this.menu.addEventListener("pointerdown", (event) => event.preventDefault()) // keep the text selected
    entries.forEach(([label, run]) => {
      const button = Object.assign(document.createElement("button"), { type: "button", className: "idea-context-menu__item" })
      button.setAttribute("role", "menuitem")
      button.innerHTML = "<span></span>"
      button.firstChild.textContent = label
      button.addEventListener("click", () => { this.close(); run() })
      this.menu.appendChild(button)
    })
  }

  items() { return [...this.menu.querySelectorAll("button:not(:disabled)")] }

  key(event) {
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); return this.close() }
    if (event.key === "Tab") return this.close()
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const items = this.items()
    items[nextIndex(event.key, items.indexOf(document.activeElement), items.length)]?.focus()
  }

  close(restore = true) {
    if (!this.menu) return
    document.removeEventListener("keydown", this.onKey, true)
    document.removeEventListener("pointerdown", this.onAway, true)
    window.removeEventListener("scroll", this.onScroll, true)
    window.removeEventListener("blur", this.onBlur)
    this.menu.remove()
    this.menu = null
    if (restore && this.opener?.isConnected) this.opener.focus?.({ preventScroll: true })
  }

  add() {
    if (this.field) {
      const f = this.field
      const { value, caret } = quoteAfterSelection(f.value, f.selectionStart, f.selectionEnd)
      f.value = value
      f.setSelectionRange(caret, caret)
      f.dispatchEvent(new Event("input", { bubbles: true }))
      return f.focus()
    }
    const annotate = this.application.getControllerForElementAndIdentifier(this.element, "kb-annotate")
    if (!annotate) return
    annotate.handleSelection(document, { type: "kb-selection-menu", target: this.element })
    annotate.paint({ params: { color: "yellow" } })
  }

  ask() {
    if (!document.getElementById("ask-agent")) return this.notice("The Ask Agent panel is not available: the local agent is not running.", "Set up the agent")
    window.dispatchEvent(new CustomEvent("ask-agent:prefill", { detail: { text: selectionPrompt("ask", this.text, this.fileValue) } }))
  }

  async expand() {
    const question = selectionPrompt("expand", this.text, this.fileValue).trim()
    const body = new FormData()
    body.append("agent_question[body]", question)
    let result
    try {
      const response = await fetch(this.questionsUrlValue, {
        method: "POST", body, credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      })
      result = { ok: response.ok, ...(await response.json().catch(() => ({}))) }
    } catch {
      return this.notice("Could not reach the server, so Expand was not sent. Try again.")
    }
    if (!result.ok) return this.notice(result.error === "disabled" ? "The local agent is turned off, so Expand cannot run." : "Expand was not sent.", "Enable the agent")
    if (document.getElementById("ask-agent")) return window.dispatchEvent(new CustomEvent("ask-agent:queued", { detail: { question } }))
    this.notice(result.live ? "Expand queued with the local agent." : "Expand queued, but the local agent is not running yet. It will answer once it starts.", "Agent settings")
  }

  // Small status toast with a link to the agent settings; replaces any previous one.
  notice(message, linkLabel) {
    document.querySelector(".kb-selection-notice")?.remove()
    const toast = Object.assign(document.createElement("div"), { className: "kb-selection-notice" })
    toast.setAttribute("role", "status")
    toast.append(Object.assign(document.createElement("span"), { textContent: message }))
    if (linkLabel && this.settingsUrlValue) toast.append(Object.assign(document.createElement("a"), { href: this.settingsUrlValue, textContent: linkLabel }))
    toast.append(Object.assign(document.createElement("button"), { type: "button", textContent: "Dismiss", onclick: () => toast.remove() }))
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 12000)
  }

  async copy() {
    try { await navigator.clipboard.writeText(this.text) } catch { document.execCommand?.("copy") }
  }
}
