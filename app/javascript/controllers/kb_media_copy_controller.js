import { Controller } from "@hotwired/stimulus"

// Makes KB images and videos explicitly selectable and copyable. Clipboard
// APIs only guarantee binary image support, so video copies include rich HTML
// plus a plain URL and use a URL-only fallback on older browsers.
export default class extends Controller {
  static targets = ["label", "status"]
  static values = {
    url: String,
    mimeType: String,
    filename: String
  }

  disconnect() {
    window.clearTimeout(this._feedbackTimer)
  }

  select(event) {
    this.element.querySelectorAll(".kb-selectable-media.is-selected")
      .forEach((media) => media.classList.remove("is-selected"))
    event.currentTarget.classList.add("is-selected")
    event.currentTarget.focus({ preventScroll: true })
  }

  copyFromShortcut(event) {
    if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "c") return

    event.preventDefault()
    this.copy()
  }

  async copy() {
    const url = new URL(this.urlValue, window.location.href).href
    this.#setFeedback("Copying…")

    try {
      if (typeof ClipboardItem === "function" && navigator.clipboard?.write) {
        const payload = {
          "text/plain": new Blob([url], { type: "text/plain" }),
          "text/html": new Blob([this.#htmlFor(url)], { type: "text/html" })
        }
        const binary = await this.#binaryClipboardEntry()
        if (binary) payload[binary.type] = binary.blob

        await navigator.clipboard.write([new ClipboardItem(payload)])
      } else {
        await navigator.clipboard.writeText(url)
      }
      this.#setFeedback("Copied", true)
    } catch {
      try {
        await navigator.clipboard.writeText(url)
        this.#setFeedback("Link copied", true)
      } catch {
        this.#setFeedback("Copy failed", true)
      }
    }
  }

  async #binaryClipboardEntry() {
    const mime = this.mimeTypeValue
    const isImage = mime.startsWith("image/")
    const targetMime = isImage ? "image/png" : mime
    if (!this.#clipboardSupports(targetMime)) return null

    const response = await fetch(this.urlValue, { credentials: "same-origin" })
    if (!response.ok) throw new Error("Media could not be read")
    const blob = await response.blob()

    if (!isImage || blob.type === "image/png") return { type: targetMime, blob }
    return { type: "image/png", blob: await this.#imageAsPng(blob) }
  }

  #clipboardSupports(type) {
    return typeof ClipboardItem.supports === "function" ? ClipboardItem.supports(type) : type === "image/png"
  }

  async #imageAsPng(blob) {
    const bitmap = await createImageBitmap(blob)
    const canvas = document.createElement("canvas")
    canvas.width = bitmap.width
    canvas.height = bitmap.height
    canvas.getContext("2d").drawImage(bitmap, 0, 0)
    bitmap.close()

    return new Promise((resolve, reject) => {
      canvas.toBlob((png) => png ? resolve(png) : reject(new Error("Image conversion failed")), "image/png")
    })
  }

  #htmlFor(url) {
    const escapedUrl = this.#escape(url)
    const escapedName = this.#escape(this.filenameValue)
    if (this.mimeTypeValue.startsWith("image/")) {
      return `<img src="${escapedUrl}" alt="${escapedName}">`
    }
    return `<video src="${escapedUrl}" controls title="${escapedName}"></video>`
  }

  #escape(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll('"', "&quot;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
  }

  #setFeedback(message, reset = false) {
    if (this.hasLabelTarget) this.labelTarget.textContent = message
    if (this.hasStatusTarget) this.statusTarget.textContent = message
    window.clearTimeout(this._feedbackTimer)
    if (!reset) return

    this._feedbackTimer = window.setTimeout(() => {
      if (this.hasLabelTarget) {
        const kind = this.mimeTypeValue.startsWith("image/") ? "image" : "video"
        this.labelTarget.textContent = `Copy ${kind}`
      }
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 1800)
  }
}
