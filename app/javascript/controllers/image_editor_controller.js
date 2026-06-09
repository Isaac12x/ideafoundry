import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "canvas", "paintBtn", "cropBtn",
    "brushSize", "brushColor", "sizeLabel",
    "cropActions", "hint"
  ]

  connect() {
    this._resolve = null
    this._originalFile = null
    this._modified = false
    this._history = []
    this._activeTool = null
    this._painting = false
    this._cropDragging = false
    this._cropStart = null
    this._cropRect = null
    this._lastPoint = null
    this._ctx = null

    this._onPointerDown = this._onPointerDown.bind(this)
    this._onPointerMove = this._onPointerMove.bind(this)
    this._onPointerUp = this._onPointerUp.bind(this)
    this._onKeyDown = this._onKeyDown.bind(this)
  }

  // ── Public API (called by dropzone via outlet) ──────────────

  edit(file) {
    return new Promise((resolve) => {
      this._resolve = resolve
      this._originalFile = file
      this._modified = false
      this._history = []
      this._activeTool = null
      this._cropRect = null
      this._updateToolState()

      const img = new Image()
      img.onload = () => {
        this._initCanvas(img)
        this._show()
        URL.revokeObjectURL(img.src)
      }
      img.src = URL.createObjectURL(file)
    })
  }

  // ── Canvas setup ────────────────────────────────────────────

  _initCanvas(img) {
    const canvas = this.canvasTarget
    const maxDim = 2000
    let w = img.naturalWidth
    let h = img.naturalHeight

    if (w > maxDim || h > maxDim) {
      const r = Math.min(maxDim / w, maxDim / h)
      w = Math.round(w * r)
      h = Math.round(h * r)
    }

    canvas.width = w
    canvas.height = h
    this._ctx = canvas.getContext("2d", { willReadFrequently: true })
    this._ctx.drawImage(img, 0, 0, w, h)
    this._saveSnapshot()
  }

  // ── Show / Hide ─────────────────────────────────────────────

  _show() {
    this.element.style.display = ""
    document.body.style.overflow = "hidden"

    const c = this.canvasTarget
    c.addEventListener("pointerdown", this._onPointerDown)
    c.addEventListener("pointermove", this._onPointerMove)
    c.addEventListener("pointerup", this._onPointerUp)
    c.addEventListener("pointerleave", this._onPointerUp)
    document.addEventListener("keydown", this._onKeyDown)
  }

  _hide() {
    this.element.style.display = "none"
    document.body.style.overflow = ""

    const c = this.canvasTarget
    c.removeEventListener("pointerdown", this._onPointerDown)
    c.removeEventListener("pointermove", this._onPointerMove)
    c.removeEventListener("pointerup", this._onPointerUp)
    c.removeEventListener("pointerleave", this._onPointerUp)
    document.removeEventListener("keydown", this._onKeyDown)

    this._history = []
    this._ctx = null
  }

  // ── Tool selection ──────────────────────────────────────────

  selectPaint() {
    this._activeTool = this._activeTool === "paint" ? null : "paint"
    this._clearCropState()
    this._updateToolState()
  }

  selectCrop() {
    this._activeTool = this._activeTool === "crop" ? null : "crop"
    this._clearCropState()
    this._updateToolState()
  }

  _updateToolState() {
    const isPaint = this._activeTool === "paint"
    const isCrop = this._activeTool === "crop"

    if (this.hasPaintBtnTarget)
      this.paintBtnTarget.classList.toggle("image-editor__tool--active", isPaint)
    if (this.hasCropBtnTarget)
      this.cropBtnTarget.classList.toggle("image-editor__tool--active", isCrop)
    if (this.hasCropActionsTarget)
      this.cropActionsTarget.style.display = "none"
    if (this.hasCanvasTarget)
      this.canvasTarget.style.cursor = (isPaint || isCrop) ? "crosshair" : "default"

    this._updateHint()
  }

  _updateHint() {
    if (!this.hasHintTarget) return
    if (this._activeTool === "paint")
      this.hintTarget.textContent = "Draw on the image"
    else if (this._activeTool === "crop")
      this.hintTarget.textContent = "Drag to select crop area"
    else
      this.hintTarget.textContent = "Select a tool to edit, or add as-is"
  }

  // ── Pointer events ──────────────────────────────────────────

  _getPoint(e) {
    const r = this.canvasTarget.getBoundingClientRect()
    return {
      x: (e.clientX - r.left) * (this.canvasTarget.width / r.width),
      y: (e.clientY - r.top) * (this.canvasTarget.height / r.height)
    }
  }

  _onPointerDown(e) {
    if (e.button !== 0) return
    const pt = this._getPoint(e)

    if (this._activeTool === "paint") {
      this._painting = true
      this._lastPoint = pt

      // Single dot
      const r = this._scaledBrush() / 2
      this._ctx.beginPath()
      this._ctx.arc(pt.x, pt.y, r, 0, Math.PI * 2)
      this._ctx.fillStyle = this.brushColorTarget.value
      this._ctx.fill()

      this.canvasTarget.setPointerCapture(e.pointerId)

    } else if (this._activeTool === "crop") {
      this._cropDragging = true
      this._cropStart = pt
      this._cropRect = null
      if (this.hasCropActionsTarget)
        this.cropActionsTarget.style.display = "none"
      this.canvasTarget.setPointerCapture(e.pointerId)
    }
  }

  _onPointerMove(e) {
    if (this._painting) {
      const pt = this._getPoint(e)
      this._strokeLine(this._lastPoint, pt)
      this._lastPoint = pt
    } else if (this._cropDragging) {
      this._drawCropOverlay(this._getPoint(e))
    }
  }

  _onPointerUp(e) {
    if (this._painting) {
      this._painting = false
      this._lastPoint = null
      this._modified = true
      this._saveSnapshot()

    } else if (this._cropDragging) {
      this._cropDragging = false
      const pt = this._getPoint(e)
      const x = Math.min(this._cropStart.x, pt.x)
      const y = Math.min(this._cropStart.y, pt.y)
      const w = Math.abs(pt.x - this._cropStart.x)
      const h = Math.abs(pt.y - this._cropStart.y)

      if (w > 5 && h > 5) {
        this._cropRect = { x, y, w, h }
        if (this.hasCropActionsTarget)
          this.cropActionsTarget.style.display = ""
      } else {
        this._restoreSnapshot()
      }
    }
  }

  _onKeyDown(e) {
    if (e.key === "Escape") {
      this._cropRect ? this.cancelCrop() : this.cancel()
    } else if ((e.metaKey || e.ctrlKey) && e.key === "z") {
      e.preventDefault()
      this.undo()
    }
  }

  // ── Paint ───────────────────────────────────────────────────

  _strokeLine(from, to) {
    const ctx = this._ctx
    const size = this._scaledBrush()
    ctx.beginPath()
    ctx.moveTo(from.x, from.y)
    ctx.lineTo(to.x, to.y)
    ctx.strokeStyle = this.brushColorTarget.value
    ctx.lineWidth = size
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.stroke()
  }

  _scaledBrush() {
    const displayW = this.canvasTarget.getBoundingClientRect().width
    const scale = this.canvasTarget.width / displayW
    return (parseInt(this.brushSizeTarget.value) || 4) * scale
  }

  updateBrushSize() {
    if (this.hasSizeLabelTarget)
      this.sizeLabelTarget.textContent = this.brushSizeTarget.value + "px"
  }

  // ── Crop ────────────────────────────────────────────────────

  _drawCropOverlay(end) {
    const start = this._cropStart
    const snap = this._history[this._history.length - 1]
    if (!snap) return

    // Restore clean state
    this._ctx.putImageData(snap, 0, 0)

    const x = Math.min(start.x, end.x)
    const y = Math.min(start.y, end.y)
    const w = Math.abs(end.x - start.x)
    const h = Math.abs(end.y - start.y)

    // Dim everything
    this._ctx.fillStyle = "rgba(0, 0, 0, 0.55)"
    this._ctx.fillRect(0, 0, this.canvasTarget.width, this.canvasTarget.height)

    // Show crop region clearly
    this._ctx.save()
    this._ctx.beginPath()
    this._ctx.rect(x, y, w, h)
    this._ctx.clip()
    this._ctx.putImageData(snap, 0, 0)
    this._ctx.restore()

    // Dashed border
    const lineW = 2 * (this.canvasTarget.width / this.canvasTarget.getBoundingClientRect().width)
    this._ctx.strokeStyle = "#d4953a"
    this._ctx.lineWidth = lineW
    this._ctx.setLineDash([8, 4])
    this._ctx.strokeRect(x, y, w, h)
    this._ctx.setLineDash([])

    // Corner handles
    const hs = 8 * (this.canvasTarget.width / this.canvasTarget.getBoundingClientRect().width)
    this._ctx.fillStyle = "#d4953a"
    for (const [cx, cy] of [[x, y], [x + w, y], [x, y + h], [x + w, y + h]]) {
      this._ctx.fillRect(cx - hs / 2, cy - hs / 2, hs, hs)
    }
  }

  applyCrop() {
    if (!this._cropRect) return
    const { x, y, w, h } = this._cropRect

    // Read from clean history (not the overlay-rendered canvas)
    const snap = this._history[this._history.length - 1]
    const tmp = document.createElement("canvas")
    tmp.width = snap.width
    tmp.height = snap.height
    tmp.getContext("2d").putImageData(snap, 0, 0)

    const cropData = tmp.getContext("2d").getImageData(
      Math.round(x), Math.round(y),
      Math.round(w), Math.round(h)
    )

    this.canvasTarget.width = Math.round(w)
    this.canvasTarget.height = Math.round(h)
    this._ctx = this.canvasTarget.getContext("2d", { willReadFrequently: true })
    this._ctx.putImageData(cropData, 0, 0)

    this._clearCropState()
    this._saveSnapshot()
    this._modified = true
  }

  cancelCrop() {
    this._restoreSnapshot()
    this._clearCropState()
  }

  _clearCropState() {
    if (this._cropRect) this._restoreSnapshot()
    this._cropRect = null
    this._cropStart = null
    if (this.hasCropActionsTarget)
      this.cropActionsTarget.style.display = "none"
  }

  // ── History ─────────────────────────────────────────────────

  _saveSnapshot() {
    const c = this.canvasTarget
    this._history.push(this._ctx.getImageData(0, 0, c.width, c.height))
    if (this._history.length > 30) this._history.shift()
  }

  _restoreSnapshot() {
    const snap = this._history[this._history.length - 1]
    if (snap) this._ctx.putImageData(snap, 0, 0)
  }

  undo() {
    if (this._history.length <= 1) return
    this._history.pop()
    const prev = this._history[this._history.length - 1]

    // Canvas may have been resized by crop — restore dimensions
    this.canvasTarget.width = prev.width
    this.canvasTarget.height = prev.height
    this._ctx = this.canvasTarget.getContext("2d", { willReadFrequently: true })
    this._ctx.putImageData(prev, 0, 0)
    this._modified = this._history.length > 1
    this._clearCropState()
  }

  reset() {
    if (this._history.length <= 1) return
    const first = this._history[0]
    this._history = [first]

    this.canvasTarget.width = first.width
    this.canvasTarget.height = first.height
    this._ctx = this.canvasTarget.getContext("2d", { willReadFrequently: true })
    this._ctx.putImageData(first, 0, 0)
    this._modified = false
    this._clearCropState()
  }

  // ── Actions ─────────────────────────────────────────────────

  add() {
    if (!this._modified) {
      this._hide()
      if (this._resolve) this._resolve(this._originalFile)
      return
    }

    const type = this._originalFile.type === "image/jpeg" ? "image/jpeg" : "image/png"
    const quality = type === "image/jpeg" ? 0.92 : undefined

    this.canvasTarget.toBlob((blob) => {
      const file = new File([blob], this._originalFile.name, {
        type,
        lastModified: Date.now()
      })
      this._hide()
      if (this._resolve) this._resolve(file)
    }, type, quality)
  }

  cancel() {
    this._hide()
    if (this._resolve) this._resolve(null)
  }
}
