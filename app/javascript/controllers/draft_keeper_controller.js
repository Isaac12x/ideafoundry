import { Controller } from "@hotwired/stimulus"
import { clearFieldDraft, draftKey, restoreFieldDraft, saveFieldDraft } from "lib/field_draft"

// Keeps unsaved textarea text on Knowledge Base / project pages across lock, reload and navigation (body-level).
// Saves while typing, restores on load with a small "Draft restored / Discard" note. A draft is cleared only once
// its save succeeded: turbo:submit-end (success), draft:clear (fetch forms call it on success), Discard, or, for
// non-Turbo posts, on the next load when the page shows no error. A rejected save keeps the text.
// draft:flush (the lock) and pagehide/visibilitychange write pending drafts immediately.
// data-draft-manual fields are saved here but restored by their own controller (editors that start hidden).
// Fields with their own persistence or sizing rules opt out via data-draft-skip; idea forms have idea-draft-persist.
const PENDING = "fielddraft:pending"
const ERROR = ".alert-error, .field_with_errors"
const FIELDS = "textarea[name]:not([data-draft-skip])"

export default class extends Controller {
  connect() {
    this.timers = new Map()
    this.on = (target, type, fn, opts) => { target.addEventListener(type, fn, opts); (this.off ||= []).push(() => target.removeEventListener(type, fn, opts)) }
    this.on(document, "input", (event) => this.queue(event.target))
    this.on(document, "submit", (event) => this.markPending(event))
    this.on(document, "turbo:submit-end", (event) => event.detail.success && this.clearForm(event.target))
    this.on(document, "draft:flush", (event) => event.detail?.wait?.push(this.flush()))
    this.on(document, "draft:clear", (event) => this.clear(event.target))
    this.on(document, "turbo:load", () => this.restoreAll())
    this.on(document, "turbo:frame-render", () => this.restoreAll())
    this.on(window, "pagehide", () => this.flush())
    this.on(document, "visibilitychange", () => document.visibilityState === "hidden" && this.flush())
    this.settlePending()
    this.restoreAll()
  }

  disconnect() {
    this.off?.forEach((fn) => fn())
    this.flush()
  }

  active() { return location.pathname.startsWith("/knowledge-base") }

  eligible(field) {
    return field?.matches?.(FIELDS) && !field.closest("[data-controller~='idea-draft-persist']")
  }

  queue(field) {
    if (!this.active() || !this.eligible(field)) return
    clearTimeout(this.timers.get(field))
    this.timers.set(field, setTimeout(() => this.save(field), 250))
  }

  save(field) {
    this.timers.delete(field)
    return saveFieldDraft(field)
  }

  // Resolves once every pending draft is written (the lock waits on it before leaving the page).
  flush() {
    return Promise.all([...(this.timers || [])].map(([field, timer]) => { clearTimeout(timer); return this.save(field) }))
  }

  clear(field) {
    clearTimeout(this.timers.get(field))
    this.timers.delete(field)
    clearFieldDraft(field)
  }

  clearForm(form) {
    if (this.active() && form instanceof HTMLFormElement) form.querySelectorAll(FIELDS).forEach((field) => this.clear(field))
  }

  // A plain (data-turbo=false) post leaves the page, so we can't see the response: remember which drafts it covered.
  markPending(event) {
    const form = event.target
    if (!this.active() || event.defaultPrevented || !(form instanceof HTMLFormElement) || !form.closest("[data-turbo='false']")) return
    const keys = [...form.querySelectorAll(FIELDS)].map(draftKey)
    try { sessionStorage.setItem(PENDING, JSON.stringify(keys)) } catch { /* private mode: the draft just stays */ }
  }

  settlePending() {
    try {
      const keys = JSON.parse(sessionStorage.getItem(PENDING) || "[]")
      sessionStorage.removeItem(PENDING)
      if (!document.querySelector(ERROR)) keys.forEach((key) => localStorage.removeItem(key))
    } catch { /* nothing pending */ }
  }

  async restoreAll() {
    if (!this.active()) return
    for (const field of document.querySelectorAll(FIELDS)) {
      if (!this.eligible(field) || field.hasAttribute("data-draft-manual") || field.dataset.draftChecked) continue
      field.dataset.draftChecked = "1"
      if (await restoreFieldDraft(field)) this.announce(field)
    }
  }

  // Never silent: say it was restored and keep Discard one click away.
  announce(field) {
    field.closest("details")?.setAttribute("open", "")
    const note = document.createElement("p")
    note.className = "draft-note"
    note.setAttribute("role", "status")
    note.append("Draft restored. ")
    const discard = Object.assign(document.createElement("button"), { type: "button", textContent: "Discard", className: "draft-note__discard" })
    discard.addEventListener("click", () => {
      field.value = field.defaultValue
      field.dispatchEvent(new Event("input", { bubbles: true }))
      this.clear(field)
      note.remove()
    })
    note.append(discard)
    field.after(note)
  }
}
