import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "zone", "placeholder"]
  static outlets = ["image-editor"]
  static values = {
    multiple: { type: Boolean, default: false },
    accept: { type: String, default: "*/*" },
    uploadUrl: { type: String, default: "" }
  }

  connect() {
    // Hide placeholder if preview already has content (edit mode)
    if (this.hasPlaceholderTarget && this.hasPreviewTarget && this.previewTarget.children.length > 0) {
      this.placeholderTarget.style.display = "none"
    }
  }

  click() {
    this.inputTarget.click()
  }

  dragover(e) {
    e.preventDefault()
  }

  dragenter(e) {
    e.preventDefault()
    if (this._acceptsFiles()) {
      this.zoneTarget.classList.add("dropzone--active")
      this.zoneTarget.classList.remove("dropzone--reject")
    } else {
      this.zoneTarget.classList.add("dropzone--reject")
      this.zoneTarget.classList.remove("dropzone--active")
    }
  }

  dragleave(e) {
    if (!this.zoneTarget.contains(e.relatedTarget)) {
      this.zoneTarget.classList.remove("dropzone--active", "dropzone--reject")
    }
  }

  drop(e) {
    e.preventDefault()
    this.zoneTarget.classList.remove("dropzone--active", "dropzone--reject")

    const dt = e.dataTransfer
    if (!dt.files.length) return

    this._handleFiles(Array.from(dt.files))
  }

  // Also handle normal file input change
  inputTargetConnected(input) {
    this._onChange ||= () => {
      if (this._processingFiles) return
      if (this.hasInputTarget && this.inputTarget.files.length) {
        this._handleFiles(Array.from(this.inputTarget.files))
      }
    }
    input.addEventListener("change", this._onChange)
  }

  inputTargetDisconnected(input) {
    input.removeEventListener("change", this._onChange)
  }

  async _handleFiles(rawFiles) {
    const accepted = this._filterAccepted(rawFiles)
    if (!accepted.length) return

    const processed = []
    for (const file of accepted) {
      if (file.type.startsWith("image/") && this.hasImageEditorOutlet) {
        const result = await this.imageEditorOutlet.edit(file)
        if (result) processed.push(result)
      } else {
        processed.push(file)
      }
    }

    if (!processed.length) {
      this.inputTarget.value = ""
      return
    }

    if (this.uploadUrlValue) {
      await this._ajaxUpload(processed)
    } else {
      // Multi-file fields accumulate: a second drop adds to the pending files instead of replacing them.
      const files = this.multipleValue ? (this._pending = [...(this._pending || []), ...processed]) : processed
      this._syncInput(files)
      this._renderPreviews(files)
    }
  }

  _syncInput(files) {
    this._processingFiles = true
    this.inputTarget.files = this._buildFileList(files)
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this._processingFiles = false
  }

  _removePending(file) {
    this._pending = this._pending.filter((f) => f !== file)
    this._syncInput(this._pending)
    this._renderGrid(this._pending)
    if (!this._pending.length && this.hasPlaceholderTarget) this.placeholderTarget.style.display = ""
  }

  async _ajaxUpload(files) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const formData = new FormData()
    files.forEach(file => formData.append("files[]", file))

    this._setUploadStatus("Uploading…")
    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        body: formData
      })

      if (response.ok) {
        const data = await response.json()
        this._setUploadStatus("")
        this.dispatch("uploaded", { detail: { html: data.html } })
        if (this.hasPreviewTarget) this.previewTarget.innerHTML = ""
        if (this.hasPlaceholderTarget) this.placeholderTarget.style.display = ""
      } else {
        this._setUploadStatus("Upload failed. Please try again.")
      }
    } catch {
      this._setUploadStatus("Upload failed. Please try again.")
    }

    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  _setUploadStatus(message) {
    const statusEl = this.element.querySelector("[data-dropzone-status]")
    if (statusEl) statusEl.textContent = message
  }

  _acceptsFiles() {
    // Best-effort: browsers don't expose file types during dragenter
    return true
  }

  _filterAccepted(files) {
    if (this.acceptValue === "*/*") return Array.from(files)
    const accept = this.acceptValue
    return Array.from(files).filter(f => {
      if (accept.includes("/*")) {
        const prefix = accept.split("/")[0]
        return f.type.startsWith(prefix + "/")
      }
      return accept.split(",").some(a => f.type === a.trim() || f.name.endsWith(a.trim()))
    })
  }

  _buildFileList(files) {
    const dt = new DataTransfer()
    files.forEach(f => dt.items.add(f))
    return dt.files
  }

  _renderPreviews(files) {
    if (this.multipleValue) {
      this._renderGrid(files)
    } else {
      this._renderHero(files[0])
    }
    // Hide placeholder when we have content
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.style.display = "none"
    }
  }

  _renderHero(file) {
    this.previewTarget.innerHTML = ""
    if (file.type.startsWith("image/")) {
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      img.style.cssText = "max-width:100%;max-height:200px;border-radius:6px;border:1px solid var(--border-default);"
      img.onload = () => URL.revokeObjectURL(img.src)
      this.previewTarget.appendChild(img)
    }
  }

  _renderGrid(files) {
    this.previewTarget.innerHTML = ""
    files.forEach(file => {
      const thumb = document.createElement("div")
      thumb.className = "dropzone__thumb"
      if (file.type.startsWith("image/")) {
        const img = document.createElement("img")
        img.src = URL.createObjectURL(file)
        img.onload = () => URL.revokeObjectURL(img.src)
        thumb.appendChild(img)
      } else {
        const label = document.createElement("div")
        label.className = "dropzone__thumb-file"
        label.textContent = file.name
        thumb.appendChild(label)
      }
      if (!this._ajax() && this._pending) {
        const remove = document.createElement("button")
        remove.type = "button"
        remove.className = "dropzone__thumb-remove"
        remove.setAttribute("aria-label", `Remove ${file.name}`)
        remove.textContent = "×"
        remove.addEventListener("click", (e) => {
          e.stopPropagation() // the zone itself opens the file picker on click
          this._removePending(file)
        })
        thumb.appendChild(remove)
      }
      this.previewTarget.appendChild(thumb)
    })
  }

  _ajax() {
    return !!this.uploadUrlValue
  }
}
