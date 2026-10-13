import { Controller } from "@hotwired/stimulus"

// Think in Images: a moodboard wall (drag/drop, free 2D arrange) + a
// fullscreen presentation mode for free-association (next/prev/random/autoplay).
export default class extends Controller {
  static targets = [
    "wall", "input", "empty", "tile",
    "stage", "stageImg", "stageCaption", "stageCounter", "playBtn"
  ]
  static values = {
    createUrl: String,
    ideaId: String
  }

  connect() {
    this._maxZ = this._currentMaxZ()
    this._onKey = this._onKey.bind(this)
  }

  disconnect() {
    this._stopPlay()
    clearTimeout(this._hideTimer)
    document.body.classList.remove("mood-stage-open")
    window.removeEventListener("keydown", this._onKey)
  }

  // ── Uploading ────────────────────────────────────────────────
  pickFiles() { this.inputTarget.click() }

  uploadFromInput() {
    if (this.inputTarget.files.length) this._upload(this.inputTarget.files)
  }

  dragOver(e) {
    if (!this._hasFiles(e)) return
    e.preventDefault()
    this.wallTarget.classList.add("is-dropping")
  }

  dragLeave(e) {
    if (!this.wallTarget.contains(e.relatedTarget)) {
      this.wallTarget.classList.remove("is-dropping")
    }
  }

  dropFiles(e) {
    this.wallTarget.classList.remove("is-dropping")
    if (!this._hasFiles(e)) return
    e.preventDefault()
    this._upload(e.dataTransfer.files)
  }

  async _upload(fileList) {
    const files = Array.from(fileList).filter(f => f.type.startsWith("image/"))
    if (!files.length) return

    const fd = new FormData()
    files.forEach(f => fd.append("files[]", f))
    if (this.ideaIdValue) fd.append("idea_id", this.ideaIdValue)

    this.element.classList.add("is-uploading")
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this._csrf(),
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: fd
      })
      if (res.ok) {
        Turbo.renderStreamMessage(await res.text())
        if (this.hasEmptyTarget) this.emptyTarget.classList.add("is-hidden")
      }
    } finally {
      this.element.classList.remove("is-uploading")
      if (this.hasInputTarget) this.inputTarget.value = ""
    }
  }

  // ── Dragging tiles on the wall ───────────────────────────────
  grab(e) {
    if (e.button !== 0) return
    const tile = e.currentTarget
    if (e.target.closest(".mood-tile__del")) return
    e.preventDefault()
    tile.setPointerCapture(e.pointerId)
    this._bringToFront(tile)
    tile.classList.add("is-dragging")

    const startX = e.clientX, startY = e.clientY
    const originLeft = parseFloat(tile.style.left) || 0
    const originTop = parseFloat(tile.style.top) || 0
    let moved = false

    const move = (ev) => {
      moved = true
      tile.style.left = `${Math.max(0, originLeft + ev.clientX - startX)}px`
      tile.style.top = `${Math.max(0, originTop + ev.clientY - startY)}px`
    }
    const up = () => {
      tile.removeEventListener("pointermove", move)
      tile.removeEventListener("pointerup", up)
      tile.classList.remove("is-dragging")
      if (moved) this._persist(tile)
    }
    tile.addEventListener("pointermove", move)
    tile.addEventListener("pointerup", up)
  }

  async remove(e) {
    e.preventDefault()
    const tile = e.currentTarget.closest(".mood-tile")
    if (!tile) return
    await fetch(tile.dataset.updateUrl, {
      method: "DELETE",
      headers: { "X-CSRF-Token": this._csrf(), "Accept": "application/json" }
    })
    tile.remove()
    if (this.tileTargets.length === 0 && this.hasEmptyTarget) {
      this.emptyTarget.classList.remove("is-hidden")
    }
  }

  stopEvent(e) { e.stopPropagation() }

  _persist(tile) {
    const body = new URLSearchParams({
      "mood_image[pos_x]": parseFloat(tile.style.left) || 0,
      "mood_image[pos_y]": parseFloat(tile.style.top) || 0,
      "mood_image[z_index]": parseInt(tile.style.zIndex) || 0
    })
    fetch(tile.dataset.updateUrl, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this._csrf(),
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body
    })
  }

  _bringToFront(tile) {
    this._maxZ += 1
    tile.style.zIndex = this._maxZ
  }

  _currentMaxZ() {
    return this.tileTargets.reduce((m, t) => Math.max(m, parseInt(t.style.zIndex) || 0), 0)
  }

  // ── Presentation mode ────────────────────────────────────────
  present() {
    this._slides = this.tileTargets.map(t => ({
      src: t.dataset.src,
      caption: t.dataset.caption || ""
    }))
    if (!this._slides.length) return
    this._pos = 0
    this._render()
    clearTimeout(this._hideTimer)
    this.stageTarget.hidden = false
    requestAnimationFrame(() => this.stageTarget.classList.add("is-open"))
    document.body.classList.add("mood-stage-open")
    window.addEventListener("keydown", this._onKey)
  }

  closeStage() {
    this._stopPlay()
    this.stageTarget.classList.remove("is-open")
    document.body.classList.remove("mood-stage-open")
    window.removeEventListener("keydown", this._onKey)
    this._hideTimer = setTimeout(() => { this.stageTarget.hidden = true }, 200)
  }

  stageBackdrop(e) {
    if (e.target === this.stageTarget) this.closeStage()
  }

  next() { this._go(this._pos + 1) }
  prev() { this._go(this._pos - 1) }

  random() {
    if (this._slides.length < 2) return
    let n = this._pos
    while (n === this._pos) n = Math.floor(Math.random() * this._slides.length)
    this._go(n)
  }

  togglePlay() {
    this._playing ? this._stopPlay() : this._startPlay()
  }

  _startPlay() {
    this._playing = true
    if (this.hasPlayBtnTarget) this.playBtnTarget.classList.add("is-on")
    this._timer = setInterval(() => this.random(), 2600)
  }

  _stopPlay() {
    this._playing = false
    if (this.hasPlayBtnTarget) this.playBtnTarget.classList.remove("is-on")
    if (this._timer) { clearInterval(this._timer); this._timer = null }
  }

  _go(n) {
    const len = this._slides.length
    this._pos = ((n % len) + len) % len
    this._render()
  }

  _render() {
    const slide = this._slides[this._pos]
    this.stageImgTarget.classList.remove("is-in")
    // Force reflow so the fade re-triggers on each change.
    void this.stageImgTarget.offsetWidth
    this.stageImgTarget.src = slide.src
    this.stageImgTarget.classList.add("is-in")
    this.stageCaptionTarget.textContent = slide.caption
    this.stageCaptionTarget.classList.toggle("is-empty", !slide.caption)
    this.stageCounterTarget.textContent = `${this._pos + 1} / ${this._slides.length}`
  }

  _onKey(e) {
    switch (e.key) {
      case "ArrowRight": e.preventDefault(); this.next(); break
      case "ArrowLeft": e.preventDefault(); this.prev(); break
      case " ": e.preventDefault(); this.togglePlay(); break
      case "r": case "R": this.random(); break
      case "Escape": this.closeStage(); break
    }
  }

  // ── Helpers ──────────────────────────────────────────────────
  _hasFiles(e) {
    return Array.from(e.dataTransfer?.types || []).includes("Files")
  }

  _csrf() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
