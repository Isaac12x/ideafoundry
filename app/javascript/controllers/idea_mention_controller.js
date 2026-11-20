import { Controller } from "@hotwired/stimulus"

// "@" autocomplete for ideas: wrap a textarea / rich editor; typing "@query" opens a list under it;
// picking inserts @[Title](idea:123), or the result's own `token` (KB project text: ideas incl. a version, KB entries,
// maxims... see Kb::References). `multiword` lets the query hold spaces ("Idea name v3"); `floating` pins the list
// under the field instead of relying on a positioned wrapper.
export default class extends Controller {
  static targets = ["list"]
  static values = { searchUrl: String, excludeId: Number, multiword: Boolean, floating: Boolean }

  disconnect() { clearTimeout(this.timer) }

  // input from the wrapped textarea / contenteditable (bubbles up to the wrapper)
  typed(event) {
    const ctx = this.mentionContext(event.target)
    if (!ctx) return this.close()
    this.ctx = ctx
    this.query(ctx.query)
  }

  // Text before the caret, if it ends in "@word" (the @ at start or after whitespace).
  mentionContext(el) {
    let before
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      if (this.multiwordValue && !el.matches("textarea, [data-mention]")) return null // project text: only fields that render markdown
      before = el.value.slice(0, el.selectionStart)
    } else {
      const sel = window.getSelection()
      if (!sel.rangeCount || !sel.isCollapsed || sel.anchorNode?.nodeType !== Node.TEXT_NODE) return null
      before = sel.anchorNode.textContent.slice(0, sel.anchorOffset)
    }
    const m = before.match(this.multiwordValue ? /(?:^|\s)@([^@\[\]()\n]{0,40})$/ : /(?:^|\s)@([^\s@\[\]()]{0,40})$/)
    return m ? { el, query: m[1], length: m[1].length + 1 } : null
  }

  query(q) {
    clearTimeout(this.timer)
    if (!q) return this.close()
    this.timer = setTimeout(async () => {
      const url = `${this.searchUrlValue}?q=${encodeURIComponent(q)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const results = (await response.json()).results.filter((r) => r.id !== this.excludeIdValue)
      this.render(results.slice(0, 8), q)
    }, 150)
  }

  render(results, q) {
    this.results = results
    this.active = results.length ? 0 : -1
    const items = results.map((r, i) => {
      const li = document.createElement("li")
      li.setAttribute("role", "option")
      li.className = "idea-kb-links__option"
      li.textContent = r.title
      if (r.kind) {
        const kind = document.createElement("small")
        kind.className = "kb-mention-kind"
        kind.textContent = r.kind
        li.append(" ", kind)
      }
      li.addEventListener("mousedown", (e) => { e.preventDefault(); this.pick(i) })
      return li
    })
    if (!items.length) {
      const li = document.createElement("li")
      li.className = "idea-kb-links__option is-empty"
      li.textContent = `No ideas match "${q}"`
      items.push(li)
    }
    this.listTarget.replaceChildren(...items)
    this.listTarget.hidden = false
    this.element.dataset.mentionOpen = "1" // lets Enter-to-submit fields stand aside while the list is open
    if (this.floatingValue && this.ctx) {
      const box = this.ctx.el.getBoundingClientRect()
      Object.assign(this.listTarget.style, { position: "fixed", top: `${box.bottom + 2}px`, left: `${box.left}px`, right: "auto", width: `${Math.min(box.width, 420)}px` })
      // Flip above the field when the list would run off the viewport bottom.
      const h = this.listTarget.offsetHeight
      if (box.bottom + 2 + h > window.innerHeight && box.top > h + 2) this.listTarget.style.top = `${box.top - h - 2}px`
    }
    this.highlight()
  }

  keydown(event) {
    if (this.listTarget.hidden) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!this.results?.length) return
      event.preventDefault()
      this.active = (this.active + (event.key === "ArrowDown" ? 1 : -1) + this.results.length) % this.results.length
      this.highlight()
    } else if (event.key === "Enter" || event.key === "Tab") {
      if (this.active < 0) return
      event.preventDefault()
      this.pick(this.active)
    } else if (event.key === "Escape") {
      event.stopPropagation()
      this.close()
    }
  }

  highlight() {
    [...this.listTarget.children].forEach((li, i) => li.setAttribute("aria-selected", i === this.active ? "true" : "false"))
    this.listTarget.children[this.active]?.scrollIntoView({ block: "nearest" })
  }

  pick(index) {
    const r = this.results[index]
    if (this.ctx) this.insertToken(r)
    this.close()
  }

  insertToken(r) {
    const { el, length } = this.ctx
    const token = `${r.token || `@[${r.title.replace(/[\[\]\n]/g, " ").trim()}](idea:${r.id})`} `
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      el.setRangeText(token, el.selectionStart - length, el.selectionStart, "end")
      el.dispatchEvent(new Event("input", { bubbles: true }))
    } else {
      // contenteditable (TipTap): select "@query" then type over it so the editor sees a normal edit
      const sel = window.getSelection()
      sel.setBaseAndExtent(sel.anchorNode, sel.anchorOffset - length, sel.anchorNode, sel.anchorOffset)
      document.execCommand("insertText", false, token)
    }
    this.ctx = null
  }

  close() {
    if (this.hasListTarget) this.listTarget.hidden = true
    delete this.element.dataset.mentionOpen
    this.results = []
  }
}
