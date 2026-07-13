import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "status", "saveButton", "canvas", "imageSource", "cropSelection",
    "drawColor", "drawSize", "annotationText", "media", "waveform",
    "trimStart", "trimEnd", "scrubber", "clock", "speed", "speedOutput",
    "volume", "volumeOutput", "mute", "brightness", "brightnessOutput",
    "contrast", "contrastOutput", "saturation", "saturationOutput",
    "grayscale", "rotate", "flipHorizontal", "flipVertical", "cropAspect"
  ]

  static values = {
    kind: String,
    filename: String,
    duration: Number,
    width: Number,
    height: Number,
    size: Number
  }

  connect() {
    this.mode = null
    this.imageHistory = []
    this.imageRecipe = []
    this.pointerActive = false
    this.pollTimer = null
    this.abortController = new AbortController()

    if (this.hasImageSourceTarget && this.imageSourceTarget.complete) this.loadImage()
    if (this.hasMediaTarget && this.mediaTarget.readyState >= 1) this.mediaReady()
    if (this.kindValue === "audio" && this.hasWaveformTarget) this.drawWaveform()
    this.preview()
  }

  disconnect() {
    window.clearTimeout(this.pollTimer)
    this.abortController?.abort()
    this.audioContext?.close()
  }

  // Image studio ---------------------------------------------------------

  loadImage() {
    const image = this.imageSourceTarget
    if (!image.naturalWidth || !this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    canvas.width = image.naturalWidth
    canvas.height = image.naturalHeight
    canvas.getContext("2d", { willReadFrequently: true }).drawImage(image, 0, 0)
    this.originalImage = this.cloneCanvas(canvas)
    this.imageHistory = [this.cloneCanvas(canvas)]
    this.preview()
  }

  setMode(event) {
    const nextMode = event.params.mode
    this.mode = this.mode === nextMode ? null : nextMode
    this.element.querySelectorAll("[data-kb-media-editor-mode-param]").forEach((button) => {
      const active = button.dataset.kbMediaEditorModeParam === this.mode
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
    if (this.hasCanvasTarget) this.canvasTarget.style.cursor = this.mode === "crop" ? "crosshair" : this.mode === "draw" ? "crosshair" : "default"
    if (this.hasStatusTarget) this.statusTarget.textContent = this.mode ? `${this.mode[0].toUpperCase()}${this.mode.slice(1)} tool active` : "Original protected in revision history"
  }

  pointerDown(event) {
    if (!this.mode || !this.hasCanvasTarget || event.button !== 0) return
    const point = this.canvasPoint(event)
    if (!point) return

    event.preventDefault()
    this.pointerActive = true
    this.pointerStart = point
    this.lastPoint = point
    event.currentTarget.setPointerCapture?.(event.pointerId)

    if (this.mode === "draw") {
      this.currentStroke = {
        tool: "draw",
        color: this.hasDrawColorTarget ? this.drawColorTarget.value : "#e0a54a",
        size: Number(this.hasDrawSizeTarget ? this.drawSizeTarget.value : 6),
        strokeWidth: Number(this.brushWidth().toFixed(3)),
        points: [[Math.round(point.x), Math.round(point.y)]]
      }
      const context = this.canvasTarget.getContext("2d")
      context.fillStyle = this.hasDrawColorTarget ? this.drawColorTarget.value : "#e0a54a"
      context.beginPath()
      context.arc(point.x, point.y, this.brushWidth() / 2, 0, Math.PI * 2)
      context.fill()
    } else if (this.mode === "crop" && this.hasCropSelectionTarget) {
      this.cropSelectionTarget.hidden = false
      this.positionCropSelection(point, point)
    }
  }

  pointerMove(event) {
    if (!this.pointerActive) return

    if (this.mode === "draw") {
      const point = this.canvasPoint(event)
      if (!point) return
      const context = this.canvasTarget.getContext("2d")
      context.beginPath()
      context.moveTo(this.lastPoint.x, this.lastPoint.y)
      context.lineTo(point.x, point.y)
      context.strokeStyle = this.hasDrawColorTarget ? this.drawColorTarget.value : "#e0a54a"
      context.lineWidth = this.brushWidth()
      context.lineCap = "round"
      context.lineJoin = "round"
      context.stroke()
      this.lastPoint = point
      if (this.currentStroke.points.length < 2_000) this.currentStroke.points.push([Math.round(point.x), Math.round(point.y)])
    } else if (this.mode === "crop") {
      this.positionCropSelection(this.pointerStart, this.canvasPoint(event))
    }
  }

  pointerUp(event) {
    if (!this.pointerActive) return
    this.pointerActive = false

    if (this.mode === "draw") {
      this.imageRecipe.push(this.currentStroke)
      this.currentStroke = null
      this.pushImageHistory()
    } else if (this.mode === "crop") {
      const finish = this.canvasPoint(event)
      this.applyCrop(this.pointerStart, finish)
      if (this.hasCropSelectionTarget) this.cropSelectionTarget.hidden = true
    }
  }

  rotateLeft() { this.rotateImage(-Math.PI / 2) }
  rotateRight() { this.rotateImage(Math.PI / 2) }

  rotateImage(radians) {
    if (!this.hasCanvasTarget || !this.canvasTarget.width) return
    const source = this.cloneCanvas(this.canvasTarget)
    const canvas = this.canvasTarget
    canvas.width = source.height
    canvas.height = source.width
    const context = canvas.getContext("2d")
    context.translate(canvas.width / 2, canvas.height / 2)
    context.rotate(radians)
    context.drawImage(source, -source.width / 2, -source.height / 2)
    this.imageRecipe.push({ tool: "rotate", degrees: radians > 0 ? 90 : -90 })
    this.pushImageHistory()
  }

  flipHorizontal() { this.flipImage(true) }
  flipVertical() { this.flipImage(false) }

  flipImage(horizontal) {
    if (!this.hasCanvasTarget || !this.canvasTarget.width) return
    const source = this.cloneCanvas(this.canvasTarget)
    const context = this.canvasTarget.getContext("2d")
    context.save()
    context.clearRect(0, 0, source.width, source.height)
    context.translate(horizontal ? source.width : 0, horizontal ? 0 : source.height)
    context.scale(horizontal ? -1 : 1, horizontal ? 1 : -1)
    context.drawImage(source, 0, 0)
    context.restore()
    this.imageRecipe.push({ tool: horizontal ? "flip_horizontal" : "flip_vertical" })
    this.pushImageHistory()
  }

  addText() {
    if (!this.hasCanvasTarget || !this.hasAnnotationTextTarget) return
    const text = this.annotationTextTarget.value.trim()
    if (!text) return

    const context = this.canvasTarget.getContext("2d")
    const size = Math.max(18, this.brushWidth() * 4)
    context.font = `600 ${size}px sans-serif`
    context.textAlign = "center"
    context.textBaseline = "middle"
    context.lineWidth = Math.max(2, size / 12)
    context.strokeStyle = "rgba(12, 12, 15, .78)"
    context.fillStyle = this.hasDrawColorTarget ? this.drawColorTarget.value : "#e0a54a"
    context.strokeText(text, this.canvasTarget.width / 2, this.canvasTarget.height / 2)
    context.fillText(text, this.canvasTarget.width / 2, this.canvasTarget.height / 2)
    this.imageRecipe.push({
      tool: "text", text, color: context.fillStyle, size,
      x: Math.round(this.canvasTarget.width / 2), y: Math.round(this.canvasTarget.height / 2)
    })
    this.annotationTextTarget.value = ""
    this.pushImageHistory()
  }

  undo() {
    if (this.imageHistory.length <= 1) return
    this.imageHistory.pop()
    this.restoreCanvas(this.imageHistory[this.imageHistory.length - 1])
    this.imageRecipe.push({ tool: "undo" })
  }

  resetImage() {
    if (!this.originalImage) return
    this.imageHistory = [this.cloneCanvas(this.originalImage)]
    this.imageRecipe.push({ tool: "reset" })
    this.restoreCanvas(this.originalImage)
    const adjustmentTargets = [
      this.hasBrightnessTarget ? this.brightnessTarget : null,
      this.hasContrastTarget ? this.contrastTarget : null,
      this.hasSaturationTarget ? this.saturationTarget : null
    ]
    adjustmentTargets.forEach((input, index) => { if (input) input.value = [0, 1, 1][index] })
    if (this.hasGrayscaleTarget) this.grayscaleTarget.checked = false
    this.preview()
  }

  applyCrop(start, finish) {
    if (!start || !finish) return
    const x = Math.max(0, Math.round(Math.min(start.x, finish.x)))
    const y = Math.max(0, Math.round(Math.min(start.y, finish.y)))
    const width = Math.min(this.canvasTarget.width - x, Math.round(Math.abs(start.x - finish.x)))
    const height = Math.min(this.canvasTarget.height - y, Math.round(Math.abs(start.y - finish.y)))
    if (width < 4 || height < 4) return

    const source = this.cloneCanvas(this.canvasTarget)
    this.canvasTarget.width = width
    this.canvasTarget.height = height
    this.canvasTarget.getContext("2d").drawImage(source, x, y, width, height, 0, 0, width, height)
    this.imageRecipe.push({ tool: "crop", x, y, width, height })
    this.pushImageHistory()
  }

  positionCropSelection(start, finish) {
    if (!this.hasCropSelectionTarget || !start || !finish) return
    const rect = this.canvasTarget.getBoundingClientRect()
    const x1 = rect.left + (start.x / this.canvasTarget.width) * rect.width
    const y1 = rect.top + (start.y / this.canvasTarget.height) * rect.height
    const x2 = rect.left + (finish.x / this.canvasTarget.width) * rect.width
    const y2 = rect.top + (finish.y / this.canvasTarget.height) * rect.height
    const parent = this.cropSelectionTarget.parentElement.getBoundingClientRect()
    Object.assign(this.cropSelectionTarget.style, {
      left: `${Math.min(x1, x2) - parent.left}px`, top: `${Math.min(y1, y2) - parent.top}px`,
      width: `${Math.abs(x2 - x1)}px`, height: `${Math.abs(y2 - y1)}px`
    })
  }

  canvasPoint(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    if (!rect.width || !rect.height) return null
    return {
      x: Math.max(0, Math.min(this.canvasTarget.width, (event.clientX - rect.left) * this.canvasTarget.width / rect.width)),
      y: Math.max(0, Math.min(this.canvasTarget.height, (event.clientY - rect.top) * this.canvasTarget.height / rect.height))
    }
  }

  brushWidth() {
    const displayScale = this.canvasTarget.width / Math.max(this.canvasTarget.getBoundingClientRect().width, 1)
    return Number(this.hasDrawSizeTarget ? this.drawSizeTarget.value : 6) * displayScale
  }

  cloneCanvas(source) {
    const clone = document.createElement("canvas")
    clone.width = source.width
    clone.height = source.height
    clone.getContext("2d").drawImage(source, 0, 0)
    return clone
  }

  restoreCanvas(source) {
    this.canvasTarget.width = source.width
    this.canvasTarget.height = source.height
    this.canvasTarget.getContext("2d").drawImage(source, 0, 0)
    this.preview()
  }

  pushImageHistory() {
    this.imageHistory.push(this.cloneCanvas(this.canvasTarget))
    if (this.imageHistory.length > 24) this.imageHistory.shift()
  }

  // Audio/video studio ---------------------------------------------------

  mediaReady() {
    if (!this.hasMediaTarget) return
    const duration = Number.isFinite(this.mediaTarget.duration) ? this.mediaTarget.duration : this.durationValue
    if (this.hasTrimEndTarget && (!Number(this.trimEndTarget.value) || Number(this.trimEndTarget.value) > duration)) this.trimEndTarget.value = duration.toFixed(3)
    if (this.hasTrimEndTarget) this.trimEndTarget.max = duration
    if (this.hasTrimStartTarget) this.trimStartTarget.max = duration
    if (this.hasScrubberTarget) this.scrubberTarget.max = duration
    this.preview()
  }

  timeChanged() {
    if (!this.hasMediaTarget) return
    const current = this.mediaTarget.currentTime
    if (this.hasClockTarget) this.clockTarget.textContent = this.formatTime(current)
    if (this.hasScrubberTarget) this.scrubberTarget.value = current
    if (this.hasTrimEndTarget && current >= Number(this.trimEndTarget.value)) {
      this.mediaTarget.pause()
      this.mediaTarget.currentTime = Number(this.trimStartTarget.value || 0)
    }
  }

  scrub() {
    if (this.hasMediaTarget && this.hasScrubberTarget) this.mediaTarget.currentTime = Number(this.scrubberTarget.value)
  }

  markIn() {
    if (this.hasTrimStartTarget && this.hasMediaTarget) this.trimStartTarget.value = this.mediaTarget.currentTime.toFixed(3)
    this.validateTrim()
  }

  markOut() {
    if (this.hasTrimEndTarget && this.hasMediaTarget) this.trimEndTarget.value = this.mediaTarget.currentTime.toFixed(3)
    this.validateTrim()
  }

  seekToIn() {
    this.validateTrim()
    if (this.hasMediaTarget) this.mediaTarget.currentTime = Number(this.trimStartTarget.value || 0)
  }

  validateTrim() {
    if (!this.hasTrimStartTarget || !this.hasTrimEndTarget) return true
    const start = Number(this.trimStartTarget.value)
    const finish = Number(this.trimEndTarget.value)
    const valid = finish > start
    this.trimEndTarget.setCustomValidity(valid ? "" : "Out must be after in")
    return valid
  }

  async drawWaveform() {
    if (!this.hasMediaTarget || !this.hasWaveformTarget) return
    if (this.sizeValue > 50 * 1024 * 1024) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "Waveform skipped for large audio; timeline editing remains available"
      return
    }
    const source = this.mediaTarget.querySelector("source")?.src || this.mediaTarget.src
    if (!source || !window.AudioContext) return

    try {
      const response = await fetch(source, { signal: this.abortController.signal })
      const bytes = await response.arrayBuffer()
      this.audioContext = new AudioContext()
      const buffer = await this.audioContext.decodeAudioData(bytes)
      const samples = buffer.getChannelData(0)
      const canvas = this.waveformTarget
      const width = Math.max(canvas.clientWidth, 320)
      const height = Math.max(canvas.clientHeight, 140)
      const ratio = window.devicePixelRatio || 1
      canvas.width = width * ratio
      canvas.height = height * ratio
      const context = canvas.getContext("2d")
      context.scale(ratio, ratio)
      context.clearRect(0, 0, width, height)
      context.strokeStyle = getComputedStyle(this.element).getPropertyValue("--accent").trim() || "#d4953a"
      context.lineWidth = 1
      context.beginPath()
      const bucket = Math.max(1, Math.floor(samples.length / width))
      for (let x = 0; x < width; x++) {
        let min = 1
        let max = -1
        const offset = x * bucket
        for (let index = 0; index < bucket; index++) {
          const value = samples[offset + index] || 0
          min = Math.min(min, value)
          max = Math.max(max, value)
        }
        context.moveTo(x, (1 + min) * height / 2)
        context.lineTo(x, (1 + max) * height / 2)
      }
      context.stroke()
    } catch (error) {
      if (error.name !== "AbortError" && this.hasStatusTarget) this.statusTarget.textContent = "Waveform preview unavailable; editing still works"
    }
  }

  // Shared preview and save ---------------------------------------------

  preview() {
    const brightness = Number(this.hasBrightnessTarget ? this.brightnessTarget.value : 0)
    const contrast = Number(this.hasContrastTarget ? this.contrastTarget.value : 1)
    const saturation = Number(this.hasSaturationTarget ? this.saturationTarget.value : 1)
    const grayscale = this.hasGrayscaleTarget && this.grayscaleTarget.checked
    const filter = `brightness(${Math.max(0, 1 + brightness)}) contrast(${contrast}) saturate(${saturation}) grayscale(${grayscale ? 1 : 0})`

    if (this.hasCanvasTarget) this.canvasTarget.style.filter = filter
    if (this.hasMediaTarget) {
      this.mediaTarget.style.filter = filter
      if (this.hasSpeedTarget) this.mediaTarget.playbackRate = Number(this.speedTarget.value)
      if (this.hasVolumeTarget) this.mediaTarget.volume = Math.min(1, Number(this.volumeTarget.value))
      if (this.hasMuteTarget) this.mediaTarget.muted = this.muteTarget.checked
      const rotation = this.hasRotateTarget ? Number(this.rotateTarget.value) : 0
      const scaleX = this.hasFlipHorizontalTarget && this.flipHorizontalTarget.checked ? -1 : 1
      const scaleY = this.hasFlipVerticalTarget && this.flipVerticalTarget.checked ? -1 : 1
      this.mediaTarget.style.transform = `rotate(${rotation}deg) scale(${scaleX}, ${scaleY})`
      this.mediaTarget.style.objectFit = this.hasCropAspectTarget && this.cropAspectTarget.value !== "original" ? "cover" : "contain"
      this.mediaTarget.style.aspectRatio = this.hasCropAspectTarget && this.cropAspectTarget.value !== "original" ? this.cropAspectTarget.value.replace(":", " / ") : "auto"
    }

    if (this.hasBrightnessOutputTarget) this.brightnessOutputTarget.textContent = brightness.toFixed(2).replace(/\.00$/, "")
    if (this.hasContrastOutputTarget) this.contrastOutputTarget.textContent = contrast.toFixed(2).replace(/\.00$/, "")
    if (this.hasSaturationOutputTarget) this.saturationOutputTarget.textContent = saturation.toFixed(2).replace(/\.00$/, "")
    if (this.hasSpeedOutputTarget) this.speedOutputTarget.textContent = `${Number(this.speedTarget.value).toFixed(2).replace(/0$/, "").replace(/\.0$/, "")}×`
    if (this.hasVolumeOutputTarget) this.volumeOutputTarget.textContent = `${Math.round(Number(this.volumeTarget.value) * 100)}%`
  }

  async save(event) {
    event.preventDefault()
    if (!this.element.reportValidity() || !this.validateTrim()) return

    this.setSavingState(true, "Preparing local edit…")
    try {
      const data = new FormData(this.element)
      if (this.kindValue === "image") {
        const blob = await this.imageBlob()
        data.append("rendered_file", blob, this.filenameValue)
        data.set("operations[client_recipe]", JSON.stringify(this.imageRecipe).slice(0, 100000))
      }

      const response = await fetch(this.element.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken() },
        body: data,
        signal: this.abortController.signal
      })
      const result = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(result.error || "The edit could not be queued.")

      this.setSavingState(true, "Rendering locally… you can keep this editor open")
      this.poll(result.status_url)
    } catch (error) {
      if (error.name !== "AbortError") this.setSavingState(false, error.message, true)
    }
  }

  imageBlob() {
    return new Promise((resolve, reject) => {
      if (!this.hasCanvasTarget || !this.canvasTarget.width) return reject(new Error("The image is still loading."))
      const output = document.createElement("canvas")
      output.width = this.canvasTarget.width
      output.height = this.canvasTarget.height
      const context = output.getContext("2d")
      context.filter = this.canvasTarget.style.filter || "none"
      context.drawImage(this.canvasTarget, 0, 0)
      const extension = this.filenameValue.split(".").pop().toLowerCase()
      const mime = ["jpg", "jpeg"].includes(extension) ? "image/jpeg" : extension === "webp" ? "image/webp" : "image/png"
      output.toBlob((blob) => blob ? resolve(blob) : reject(new Error("The browser could not render this image.")), mime, 0.94)
    })
  }

  async poll(url) {
    try {
      const response = await fetch(url, { headers: { "Accept": "application/json" }, signal: this.abortController.signal })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Could not read edit status.")

      if (result.status === "done") {
        this.setSavingState(true, "Saved. Opening the new revision…")
        const frame = document.getElementById("kb-content")
        const destination = new URL(result.file_url, window.location.origin)
        destination.searchParams.set("edited", Date.now())
        if (frame) frame.src = destination.toString()
      } else if (result.status === "failed") {
        this.setSavingState(false, result.error || "The local editor failed.", true)
      } else {
        this.pollTimer = window.setTimeout(() => this.poll(url), 1000)
      }
    } catch (error) {
      if (error.name !== "AbortError") this.setSavingState(false, error.message, true)
    }
  }

  setSavingState(saving, message, error = false) {
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = saving
      this.saveButtonTarget.textContent = saving ? "Rendering…" : "Save edit"
    }
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.classList.toggle("is-error", error)
    }
  }

  formatTime(seconds) {
    const minutes = Math.floor(seconds / 60)
    const remainder = seconds - minutes * 60
    return `${String(minutes).padStart(2, "0")}:${remainder.toFixed(3).padStart(6, "0")}`
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
