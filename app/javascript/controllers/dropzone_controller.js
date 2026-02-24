import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "zone", "placeholder"]
  static values = {
    multiple: { type: Boolean, default: false },
    accept: { type: String, default: "*/*" }
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

    const accepted = this._filterAccepted(dt.files)
    if (!accepted.length) return

    this.inputTarget.files = this._buildFileList(accepted)

    // Trigger change event so Rails picks it up
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    this._renderPreviews(accepted)
  }

  // Also handle normal file input change
  inputTargetConnected() {
    this.inputTarget.addEventListener("change", () => {
      if (this.inputTarget.files.length) {
        this._renderPreviews(Array.from(this.inputTarget.files))
      }
    })
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
      this.previewTarget.appendChild(thumb)
    })
  }
}
