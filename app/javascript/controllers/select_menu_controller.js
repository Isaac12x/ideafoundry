import { Controller } from "@hotwired/stimulus"

// Progressively enhances a native <select data-controller="select-menu"> into an app-styled listbox.
// The trigger copies the select's `class` (plus `select-menu-trigger`), so callers style it with existing classes (kbp-tag, kbp-status...).
// <option data-tone="success|warning|muted|accent|danger|info"> adds a colour dot.
let uid = 0

export default class extends Controller {
  connect() {
    if (this.trigger) return
    const select = this.element
    const id = `select-menu-${++uid}`
    this.trigger = document.createElement("button")
    this.trigger.type = "button"
    this.trigger.className = `${select.className} select-menu-trigger`.trim()
    this.trigger.setAttribute("aria-haspopup", "listbox")
    this.trigger.setAttribute("aria-expanded", "false")
    this.trigger.setAttribute("aria-controls", id)
    const label = select.getAttribute("aria-label")
    if (label) this.trigger.setAttribute("aria-label", label)
    this.labelEl = document.createElement("span")
    this.labelEl.className = "select-menu-label"
    const chevron = document.createElement("span")
    chevron.className = "select-menu-chevron"
    chevron.setAttribute("aria-hidden", "true")
    this.trigger.append(this.labelEl, chevron)

    this.popover = document.createElement("div")
    this.popover.className = "select-menu-popover"
    this.popover.id = id
    this.popover.setAttribute("role", "listbox")
    this.popover.hidden = true

    this.onTriggerClick = () => (this.isOpen ? this.close() : this.open())
    this.onKey = (e) => this.keydown(e)
    this.onOutside = (e) => { if (!this.popover.contains(e.target) && !this.trigger.contains(e.target)) this.close() }
    this.onScroll = (e) => { if (!this.popover.contains(e.target)) this.close() }
    this.onClose = () => this.close()
    this.onSelectChange = () => this.sync()
    this.trigger.addEventListener("click", this.onTriggerClick)
    this.trigger.addEventListener("keydown", this.onKey)
    select.addEventListener("change", this.onSelectChange)

    select.classList.add("select-menu-native")
    select.tabIndex = -1
    select.setAttribute("aria-hidden", "true")
    select.after(this.trigger)
    document.body.append(this.popover)
    this.sync()
  }

  disconnect() {
    if (!this.trigger) return
    this.close()
    this.element.removeEventListener("change", this.onSelectChange)
    this.trigger.remove()
    this.popover.remove()
    this.element.classList.remove("select-menu-native")
    this.element.removeAttribute("tabindex")
    this.element.removeAttribute("aria-hidden")
    this.trigger = this.popover = null
  }

  get isOpen() { return !this.popover.hidden }
  get options() { return Array.from(this.element.options) }

  // Refresh label, disabled state and option list from the native select.
  sync() {
    const sel = this.element.options[this.element.selectedIndex]
    this.labelEl.textContent = sel ? sel.textContent.trim() : ""
    this.trigger.disabled = this.element.disabled
    this.setTone(this.trigger, sel?.dataset?.tone)
  }

  setTone(el, tone) {
    if (tone) el.dataset.tone = tone
    else delete el.dataset.tone
  }

  build() {
    this.popover.replaceChildren()
    this.items = this.options.map((opt, i) => {
      const el = document.createElement("div")
      el.className = "select-menu-option"
      el.id = `${this.popover.id}-${i}`
      el.setAttribute("role", "option")
      el.setAttribute("aria-selected", String(i === this.element.selectedIndex))
      if (opt.disabled) el.setAttribute("aria-disabled", "true")
      const dot = document.createElement("span")
      dot.className = "select-menu-dot"
      this.setTone(dot, opt.dataset?.tone)
      const text = document.createElement("span")
      text.className = "select-menu-option-label"
      text.textContent = opt.textContent.trim()
      const check = document.createElement("span")
      check.className = "select-menu-check"
      check.setAttribute("aria-hidden", "true")
      el.append(dot, text, check)
      el.addEventListener("click", () => { if (!opt.disabled) this.choose(i) })
      el.addEventListener("mousemove", () => { if (!opt.disabled) this.highlight(i) })
      this.popover.append(el)
      return el
    })
  }

  open() {
    if (this.isOpen || this.element.disabled) return
    this.build()
    this.popover.hidden = false
    this.place()
    this.trigger.setAttribute("aria-expanded", "true")
    this.highlight(this.element.selectedIndex >= 0 && !this.options[this.element.selectedIndex].disabled ? this.element.selectedIndex : this.step(-1, 1))
    document.addEventListener("pointerdown", this.onOutside, true)
    window.addEventListener("scroll", this.onScroll, true)
    window.addEventListener("resize", this.onClose)
  }

  close() {
    if (!this.trigger || !this.isOpen) return
    this.popover.hidden = true
    this.trigger.setAttribute("aria-expanded", "false")
    this.trigger.removeAttribute("aria-activedescendant")
    document.removeEventListener("pointerdown", this.onOutside, true)
    window.removeEventListener("scroll", this.onScroll, true)
    window.removeEventListener("resize", this.onClose)
  }

  // position: fixed from the trigger rect; flips above when below lacks room.
  place() {
    const r = this.trigger.getBoundingClientRect()
    const h = this.popover.offsetHeight || 0
    const gap = 4
    const below = window.innerHeight - r.bottom - gap
    const up = h > below && r.top > below
    const style = this.popover.style
    style.minWidth = `${r.width}px`
    style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - (this.popover.offsetWidth || r.width) - 8))}px`
    style.top = up ? `${Math.max(8, r.top - gap - h)}px` : `${r.bottom + gap}px`
    style.maxHeight = `${Math.max(120, (up ? r.top : below) - 12)}px`
    this.popover.dataset.placement = up ? "top" : "bottom"
  }

  // Next enabled index from `from` in direction `dir`, clamped (no wrap); -1 if none.
  step(from, dir) {
    const opts = this.options
    for (let i = from + dir; i >= 0 && i < opts.length; i += dir) if (!opts[i].disabled) return i
    return from < 0 || from >= opts.length ? -1 : from
  }

  highlight(i) {
    if (i < 0 || !this.items?.[i]) return
    this.active = i
    this.items.forEach((el, n) => el.classList.toggle("is-active", n === i))
    this.trigger.setAttribute("aria-activedescendant", this.items[i].id)
    this.items[i].scrollIntoView?.({ block: "nearest" })
  }

  choose(i) {
    const opt = this.options[i]
    const changed = i !== this.element.selectedIndex
    this.close()
    if (changed && opt && !opt.disabled) {
      this.element.value = opt.value
      this.sync()
      this.element.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.trigger.focus()
  }

  keydown(e) {
    const k = e.key
    if (!this.isOpen) {
      if (["Enter", " ", "ArrowDown", "ArrowUp"].includes(k)) { e.preventDefault(); this.open() }
      return
    }
    const opts = this.options
    if (k === "Escape") { e.preventDefault(); e.stopPropagation(); this.close(); this.trigger.focus() }
    else if (k === "Tab") this.close()
    else if (k === "ArrowDown") { e.preventDefault(); this.highlight(this.step(this.active, 1)) }
    else if (k === "ArrowUp") { e.preventDefault(); this.highlight(this.step(this.active, -1)) }
    else if (k === "Home") { e.preventDefault(); this.highlight(this.step(-1, 1)) }
    else if (k === "End") { e.preventDefault(); this.highlight(this.step(opts.length, -1)) }
    else if (k === "Enter" || k === " ") { e.preventDefault(); if (!opts[this.active]?.disabled) this.choose(this.active) }
    else if (k.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      // type-ahead: next enabled option starting with the letter, wrapping
      const c = k.toLowerCase()
      const n = opts.length
      for (let d = 1; d <= n; d++) {
        const i = (this.active + d) % n
        if (!opts[i].disabled && opts[i].textContent.trim().toLowerCase().startsWith(c)) { this.highlight(i); break }
      }
    }
  }
}
