import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "filenameInput", "fileInput", "deleteBtn"]
  static values = {
    updateUrl: String,
    destroyUrl: String,
    contentType: String,
    attachmentId: Number
  }

  open(event) {
    if (event.target.closest("button, a, input")) return
    this._populate(event.currentTarget)
    this.element.showModal()
  }

  openDelete(event) {
    event.stopPropagation()
    const item = event.currentTarget.closest("[data-attachment-id]")
    if (!item) return
    this._populate(item)
    this.element.showModal()
    this.deleteBtnTarget.focus()
  }

  backdropClose(event) {
    if (event.target === this.element) this.close()
  }

  save() {
    const filename = this.filenameInputTarget.value.trim()
    const file = this.fileInputTarget.files[0]
    if (!filename && !file) { this.close(); return }

    const token = document.querySelector("meta[name='csrf-token']")?.content
    const body = new FormData()
    if (filename) body.append("filename", filename)
    if (file) body.append("file", file)

    fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: { "X-CSRF-Token": token, "Accept": "application/json" },
      body
    })
      .then(r => r.json())
      .then(data => {
        if (!data.success) return
        const item = document.querySelector(`[data-attachment-id="${this.attachmentIdValue}"]`)
        if (item) {
          item.outerHTML = data.html
          const updated = document.querySelector(`[data-attachment-id="${this.attachmentIdValue}"]`)
          updated?.dispatchEvent(new CustomEvent("attachment:updated", { bubbles: true }))
        }
        this.close()
      })
  }

  async confirmDelete() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.destroyUrlValue, {
      method: "DELETE",
      headers: { "X-CSRF-Token": token, "Accept": "application/json" }
    })
    if (response.ok || response.status === 204) {
      const item = document.querySelector(`[data-attachment-id="${this.attachmentIdValue}"]`)
      if (item) {
        const container = item.closest("[data-controller~='attachment-reorder']")
        item.remove()
        container?.dispatchEvent(new CustomEvent("attachment:removed", { bubbles: true }))
      }
      this.close()
    }
  }

  close() {
    this.element.close()
    this.previewTarget.innerHTML = ""
    this.filenameInputTarget.value = ""
    this.fileInputTarget.value = ""
  }

  _populate(item) {
    const { attachmentId, destroyUrl, updateUrl, filename, url, contentType } = item.dataset
    this.attachmentIdValue = Number(attachmentId)
    this.destroyUrlValue = destroyUrl
    this.updateUrlValue = updateUrl
    this.filenameInputTarget.value = filename || ""
    this.fileInputTarget.value = ""
    this._renderPreview(url, contentType)
  }

  _renderPreview(url, contentType) {
    this.previewTarget.innerHTML = ""
    if (!url) return
    if (contentType?.startsWith("image/")) {
      const img = document.createElement("img")
      img.src = url
      img.className = "attachment-viewer-modal__img"
      this.previewTarget.appendChild(img)
    } else if (contentType === "application/pdf") {
      const embed = document.createElement("embed")
      embed.src = url
      embed.type = "application/pdf"
      embed.className = "attachment-viewer-modal__embed"
      this.previewTarget.appendChild(embed)
    } else {
      const icon = document.createElement("div")
      icon.className = "attachment-viewer-modal__icon"
      icon.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" width="48" height="48"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" /></svg>`
      this.previewTarget.appendChild(icon)
    }
  }
}
