import { Controller } from "@hotwired/stimulus"
import { nearestLine } from "lib/kb_ocr_select"

// "Live Text" for KB images: fetches OCR line boxes (local tesseract, see
// Kb::ImageOcr) and lays transparent, drag-selectable text over the image.
// The same text is available as a plain selectable panel.
export default class extends Controller {
  static targets = ["image", "layer", "status", "toggle", "panel", "text"]
  static values = { url: String }

  connect() {
    this.lines = []
    if (!this.urlValue) return // view-only format (svg, ico, avif): no OCR
    this.resizer = new ResizeObserver(() => this.layout())
    this.resizer.observe(this.imageTarget)
    this.poll(0)
  }

  disconnect() {
    this.stopDrag()
    this.resizer?.disconnect()
    window.clearTimeout(this.timer)
    this.gone = true
  }

  async poll(attempt) {
    if (this.gone) return
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) throw new Error("ocr request failed")
      const result = await response.json()
      if (result.status === "running" && attempt < 60) {
        this.timer = window.setTimeout(() => this.poll(attempt + 1), 1500)
        return this.say("Reading text…")
      }
      this.show(result)
    } catch {
      this.say("Text could not be read.")
    }
  }

  show(result) {
    if (result.status === "unavailable") {
      this.say(result.fallback_text ? "OCR unavailable; showing extracted text." : "OCR is not installed.")
      return this.setText(result.fallback_text || "")
    }
    if (result.error) return this.say(result.error)
    this.lines = result.lines || []
    this.setText(result.text || "")
    this.render()
    this.say(this.lines.length ? "" : "No text found.")
  }

  setText(text) {
    this.fullText = text
    if (this.hasTextTarget) this.textTarget.textContent = text
    this.toggleTarget.hidden = !text
  }

  render() {
    this.layerTarget.replaceChildren(...this.lines.map((line) => {
      const box = document.createElement("div")
      box.className = "kb-ocr-line"
      box.style.cssText = `left:${line.x}%;top:${line.y}%;width:${line.w}%;height:${line.h}%`
      const text = document.createElement("span")
      text.textContent = line.text
      box.append(text, "\n") // keeps line breaks when a multi-line selection is copied
      return box
    }))
    // Text layer owns drags: no native image drag, and the layer catches drags that start on empty image area.
    this.imageTarget.draggable = this.lines.length === 0
    this.layerTarget.classList.toggle("is-live", this.lines.length > 0)
    this.layout()
  }

  // Drags that start or end in empty overlay space: native selection only works over a text box,
  // so extend it to the nearest line/caret ourselves. Over text the browser stays in charge.
  dragStart(event) {
    if (event.button !== 0 || !this.lines.length) return
    this.stopDrag()
    this.native = !!event.target.closest(".kb-ocr-line")
    this.anchor = this.native ? null : this.caretAt(event.clientX, event.clientY)
    if (!this.native && this.anchor) {
      event.preventDefault() // no native image/selection start from empty space
      window.getSelection().setBaseAndExtent(this.anchor.node, this.anchor.offset, this.anchor.node, this.anchor.offset)
    }
    this.moveHandler = (e) => this.dragMove(e)
    document.addEventListener("pointermove", this.moveHandler)
    document.addEventListener("pointerup", () => this.stopDrag(), { once: true })
  }

  dragMove(event) {
    // Native drag over text: leave it to the browser.
    if (this.native && document.elementFromPoint(event.clientX, event.clientY)?.closest(".kb-ocr-line")) return
    const focus = this.caretAt(event.clientX, event.clientY)
    if (!focus) return
    const selection = window.getSelection()
    // Native mouse handling runs after pointermove and would undo the extend, so apply on the next frame.
    if (this.native && selection.anchorNode) requestAnimationFrame(() => selection.anchorNode && selection.extend(focus.node, focus.offset))
    else if (this.anchor) selection.setBaseAndExtent(this.anchor.node, this.anchor.offset, focus.node, focus.offset)
  }

  stopDrag() {
    if (this.moveHandler) document.removeEventListener("pointermove", this.moveHandler)
    this.moveHandler = null
  }

  // {node, offset} text caret nearest to a client point, clamped onto a line.
  caretAt(clientX, clientY) {
    const rect = this.layerTarget.getBoundingClientRect()
    if (!rect.width || !rect.height) return null
    const hit = nearestLine(this.lines, ((clientX - rect.left) / rect.width) * 100, ((clientY - rect.top) / rect.height) * 100)
    if (!hit) return null
    const text = this.layerTarget.children[hit.index]?.firstChild?.firstChild
    if (!text) return null
    if (hit.side === "before") return { node: text, offset: 0 }
    if (hit.side === "after") return { node: text, offset: text.length }
    // Inside the line box: ask the browser, with y pinned to the line's middle.
    const line = this.lines[hit.index]
    const y = rect.top + ((line.y + line.h / 2) / 100) * rect.height
    const pos = document.caretPositionFromPoint?.(clientX, y)
    if (pos?.offsetNode === text) return { node: text, offset: pos.offset }
    const range = document.caretRangeFromPoint?.(clientX, y)
    return range?.startContainer === text ? { node: text, offset: range.startOffset } : { node: text, offset: 0 }
  }

  // A plain click on the layer (no drag-selection) selects the image like a click on it would.
  pick() {
    if (window.getSelection().isCollapsed) this.imageTarget.click()
  }

  // Size each line's text so it covers its box: font from box height, then
  // stretch horizontally to the measured width.
  layout() {
    const image = this.imageTarget
    if (!this.lines.length || !image.clientHeight) return
    this.layerTarget.querySelectorAll(".kb-ocr-line").forEach((box, index) => {
      const text = box.firstChild
      const target = this.lines[index]
      const boxHeight = (target.h / 100) * image.clientHeight
      const boxWidth = (target.w / 100) * image.clientWidth
      box.style.fontSize = `${boxHeight * 0.85}px`
      box.style.lineHeight = `${boxHeight}px`
      text.style.transform = "none"
      text.style.transform = `scaleX(${fitScale(boxWidth, text.offsetWidth)})`
    })
  }

  togglePanel() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.toggleTarget.setAttribute("aria-pressed", String(open))
  }

  async copyAll() {
    try {
      await navigator.clipboard.writeText(this.fullText)
      this.say("Text copied.")
    } catch {
      this.say("Copy failed.")
    }
  }

  say(message) {
    this.statusTarget.textContent = message
  }
}

// Horizontal stretch from measured text width to the OCR box width.
function fitScale(boxWidth, textWidth) {
  return textWidth > 0 && boxWidth > 0 ? boxWidth / textWidth : 1
}
