import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "lib/app_dialog"

// Project page behaviours: autosave of inline fields, the private toggle
// (turning it off needs an explicit confirm), repeatable measurement rows,
// inline findings, jump links, and keeping scroll/focus across the re-render
// every save triggers (the controller is rebuilt with the new HTML).
let carried = null // { key, top, focus, at } survives the disconnect/connect

export default class extends Controller {
  static values = { key: String }

  connect() {
    this.rail = this.element.querySelector(".kbp-rail-form")
    if (this.rail) {
      this.onRailScroll = () => this.railEdges()
      this.rail.addEventListener("scroll", this.onRailScroll, { passive: true })
      if (typeof ResizeObserver !== "undefined") {
        // the rail box (viewport changes) and its content (web fonts settling) both move stage boundaries
        this.railObserver = new ResizeObserver(() => this.centerRail())
        this.railObserver.observe(this.rail)
        this.railObserver.observe(this.rail.querySelector(".kbp-stages"))
      }
      document.fonts?.ready.then(() => { if (this.rail?.isConnected) this.centerRail() })
      this.centerRail()
    }
    if (!carried || carried.key !== this.keyValue || Date.now() - carried.at > 5000) return

    const scroller = this.element.closest(".kb-content-area")
    if (scroller) scroller.scrollTop = carried.top
    if (carried.focus) this.element.querySelector(`[data-refocus="${carried.focus}"] input`)?.focus({ preventScroll: true })
    carried = null
  }

  disconnect() {
    this.rail?.removeEventListener("scroll", this.onRailScroll)
    this.railObserver?.disconnect()
  }

  // Bring the current stage into view without cutting a label at the left edge:
  // scroll to the first whole stage that still leaves the current one visible.
  centerRail() {
    const rail = this.rail
    const current = rail.querySelector(".is-current")
    if (!current) return

    // Stage boundaries, as scroll offsets that put a whole stage at the left padding.
    const stages = [...rail.querySelectorAll(".kbp-stage")]
    const first = stages[0].offsetLeft
    const max = Math.max(0, rail.scrollWidth - rail.clientWidth)
    const want = Math.min(max, Math.max(0, current.offsetLeft + current.offsetWidth / 2 - rail.clientWidth / 2))
    const bounds = stages.map((stage) => stage.offsetLeft - first)
    const fits = (offset) => current.offsetLeft >= offset + first && current.offsetLeft + current.offsetWidth <= offset + rail.clientWidth
    // Only stage boundaries (never a half label at the left), reachable, and showing the current stage whole.
    const candidates = bounds.filter((offset) => offset <= max + 1 && fits(offset))
    const chosen = candidates.reduce((best, offset) => (Math.abs(offset - want) < Math.abs(best - want) ? offset : best), candidates[0] ?? 0)
    rail.scrollLeft = want === 0 ? 0 : chosen
    this.railEdges()
  }

  // Fade masks show only on the side that has more to scroll to.
  railEdges() {
    const rail = this.rail
    const nav = rail.closest(".kbp-rail")
    nav.classList.toggle("has-left", rail.scrollLeft > 2)
    nav.classList.toggle("has-right", rail.scrollLeft + rail.clientWidth < rail.scrollWidth - 2)
  }

  // Whole report as markdown to the clipboard, with a textarea fallback.
  async copyReport(event) {
    const button = event.currentTarget
    const text = button.dataset.markdown
    let copied = false
    try {
      await navigator.clipboard.writeText(text)
      copied = true
    } catch {
      const field = document.createElement("textarea")
      field.value = text
      field.setAttribute("readonly", "")
      field.style.cssText = "position:fixed;opacity:0;top:0"
      document.body.appendChild(field)
      field.select()
      try { copied = document.execCommand("copy") } catch { copied = false }
      field.remove()
    }
    const label = button.dataset.label ||= button.textContent
    button.textContent = copied ? "Copied" : "Copy failed"
    clearTimeout(this.copyTimer)
    this.copyTimer = setTimeout(() => { button.textContent = label }, 1600)
  }

  // "Lock with password": a quiet header action that opens the form panel under the title.
  toggleLock() {
    const panel = this.element.querySelector("#kbp-lockpanel")
    if (!panel) return

    if (panel.hidden) {
      panel.hidden = false
      panel.querySelector("input")?.focus()
    } else {
      this.closeLock()
    }
    this.syncLockToggle(panel)
  }

  closeLock() {
    const panel = this.element.querySelector("#kbp-lockpanel")
    if (!panel) return

    panel.hidden = true
    panel.reset()
    this.syncLockToggle(panel)
    this.element.querySelector('[aria-controls="kbp-lockpanel"]')?.focus()
  }

  syncLockToggle(panel) {
    this.element.querySelector('[aria-controls="kbp-lockpanel"]')?.setAttribute("aria-expanded", String(!panel.hidden))
  }

  print() {
    window.print()
  }

  // Fill the conclusion editor with the server-built skeleton.
  async draft(event) {
    const button = event.currentTarget
    const field = button.closest("form").querySelector("textarea")
    if (field.value.trim()) {
      const replace = await confirmDialog("Replace the text in the editor with a draft built from your findings?", {
        title: "Replace conclusion text?", confirmLabel: "Replace"
      })
      if (!replace) return
    }
    field.value = button.dataset.draft
    field.focus()
    field.setSelectionRange(0, 0)
    field.scrollTop = 0
  }

  remember(event) {
    carried = {
      key: this.keyValue,
      top: this.element.closest(".kb-content-area")?.scrollTop ?? 0,
      focus: event.target.dataset?.refocus || null,
      at: Date.now()
    }
  }

  // Reveal a card/section from a link: opens it and every collapsed ancestor.
  jump(event) {
    event.preventDefault()
    const target = document.getElementById(event.currentTarget.dataset.target)
    if (!target) return
    for (let node = target; node; node = node.parentElement?.closest("[data-controller~='kb-collapse']")) {
      node.dispatchEvent(new CustomEvent("kb-collapse:open"))
    }
    target.scrollIntoView({ block: "start" })
  }

  // Enter saves, Shift+Enter is a new line, Esc cancels an edit.
  findingKey(event) {
    const field = event.currentTarget
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      if (field.value.trim()) field.form.requestSubmit()
    } else if (event.key === "Escape" && field.form.dataset.cancelable) {
      this.closeFinding(event)
    }
  }

  openFinding(event) {
    const item = event.currentTarget.closest(".kbp-finding")
    item.classList.add("is-editing")
    const field = item.querySelector("textarea")
    field.focus()
    field.setSelectionRange(field.value.length, field.value.length)
  }

  closeFinding(event) {
    const item = event.currentTarget.closest(".kbp-finding")
    item.classList.remove("is-editing")
    const field = item.querySelector("textarea")
    field.value = field.defaultValue
  }

  async confirmDeleteFinding(event) {
    const form = event.currentTarget
    if (form.dataset.confirmed === "1") return

    event.preventDefault()
    const confirmed = await confirmDialog("Delete this finding?", {
      title: "Delete finding?", confirmLabel: "Delete", variant: "danger"
    })
    if (!confirmed) return
    form.dataset.confirmed = "1"
    form.requestSubmit()
  }

  submit(event) {
    event.currentTarget.form?.requestSubmit()
  }

  async togglePrivate(event) {
    event.preventDefault()
    const button = event.currentTarget
    if (button.dataset.next === "0") {
      const confirmed = await confirmDialog(
        "AI jobs, agent tools and extraction will be able to read everything in this project.",
        { title: "Make this project not private?", confirmLabel: "Make not private", variant: "danger" }
      )
      if (!confirmed) return
    }
    button.form.elements.private.value = button.dataset.next
    button.form.requestSubmit()
  }

  // Deleting a test removes its folder, every run and every attached file.
  async confirmDeleteTest(event) {
    const form = event.currentTarget
    if (form.dataset.confirmed === "1") return

    event.preventDefault()
    const runs = Number(form.dataset.runCount)
    const detail = runs ? ` and its ${runs === 1 ? "run" : `${runs} runs`}, with all attached files` : ""
    const confirmed = await confirmDialog(`Delete "${form.dataset.testName}"${detail}?`, {
      title: "Delete test?", confirmLabel: "Delete", variant: "danger"
    })
    if (!confirmed) return
    form.dataset.confirmed = "1"
    form.requestSubmit()
  }

  // Reveal the inline note input for a material row.
  openNote(event) {
    const row = event.currentTarget.closest(".kbp-mat")
    const input = row.querySelector(".kbp-mat-note-input")
    input.hidden = false
    row.querySelector("[data-note-text]")?.setAttribute("hidden", "")
    input.focus()
  }

  closeNote(event) {
    const input = event.currentTarget
    input.hidden = true
    input.closest(".kbp-mat").querySelector("[data-note-text]")?.removeAttribute("hidden")
  }

  addMeasure(event) {
    const set = event.currentTarget.closest("fieldset")
    const row = set.querySelector("template").content.cloneNode(true)
    set.querySelector(".kbp-measure-rows").appendChild(row)
    set.querySelector(".kbp-measure-rows .kbp-measure:last-child input")?.focus()
  }

  removeMeasure(event) {
    const row = event.currentTarget.closest(".kbp-measure")
    const rows = row.parentElement
    row.remove()
    if (!rows.children.length) rows.closest("fieldset").querySelector("[data-action~='kb-project#addMeasure']").click()
  }
}
