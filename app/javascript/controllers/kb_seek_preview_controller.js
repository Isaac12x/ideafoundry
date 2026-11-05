import { Controller } from "@hotwired/stimulus"
import { clock } from "lib/kb_zoom"
import { timeFromPointer, clampLeft, bucketStep, bucketTime } from "lib/kb_seek_preview"

// YouTube-style frame preview over the custom seek bar (hover and drag). A hidden muted second <video>
// is created lazily on first hover (so switching videos stays cheap), seeks coalesced to the latest wanted
// time, and drawn frames are cached per time bucket. The main video is untouched until release.
const THUMB_W = 160
const CACHE_MAX = 80
const COARSE = 24 // evenly spaced frames decoded in idle time after the first hover, so a drag shows something near at once

export default class extends Controller {
  static targets = ["video", "seek", "thumb", "canvas", "stamp"]

  connect() {
    this._cache = new Map()
    this._coarse = new Map()
    this._off = []
    for (const type of ["pointerenter", "pointermove", "pointerdown"]) this.listen(this.seekTarget, type, (e) => this.move(e))
    this.listen(this.seekTarget, "pointerenter", () => { this._hover = true })
    this.listen(this.seekTarget, "pointerleave", () => { this._hover = false; if (!this._dragging) this.hide() })
    this.listen(this.seekTarget, "pointerdown", () => { this._dragging = true })
    this.listen(document, "pointermove", (e) => { if (this._dragging) this.move(e) }) // keep following when the drag leaves the bar
    for (const type of ["pointerup", "pointercancel"]) this.listen(document, type, () => { this._dragging = false; if (!this._hover) this.hide() })
    this.listen(this.videoTarget, "emptied", () => this.reset())
    this.listen(this.videoTarget, "loadstart", () => this.reset())
  }

  disconnect() {
    this._off.forEach((off) => off())
    this.reset()
  }

  listen(target, type, handler) {
    target.addEventListener(type, handler)
    this._off.push(() => target.removeEventListener(type, handler))
  }

  move(event) {
    const main = this.videoTarget
    const duration = main.duration
    if (!(duration > 0)) return
    const rect = this.seekTarget.getBoundingClientRect()
    const time = timeFromPointer(event.clientX, rect, duration)
    this.place(event.clientX, rect, time)
    this.seekTarget.style.setProperty("--h", `${(time / duration) * 100}%`)
    this.want(bucketTime(time, bucketStep(duration)))
  }

  place(clientX, seekRect, time) {
    const player = this.element.getBoundingClientRect()
    const thumb = this.thumbTarget
    const video = this.videoTarget
    const ratio = video.videoWidth && video.videoHeight ? video.videoHeight / video.videoWidth : 9 / 16
    const width = Math.min(THUMB_W, player.width)
    const height = Math.round(width * ratio)
    // Resizing a canvas blanks it, so only when the size really changed (not on every pointer move).
    if (this.canvasTarget.width !== width || this.canvasTarget.height !== height) {
      Object.assign(this.canvasTarget, { width, height })
      this._cache.clear()
      this._coarse.clear()
      if (this._probe) this.planCoarse()
    }
    thumb.hidden = false
    const left = clampLeft(clientX - player.left, width, player.width)
    thumb.style.left = `${left}px`
    thumb.style.setProperty("--notch", `${Math.min(Math.max(clientX - player.left - left, 8), width - 8)}px`)
    thumb.style.bottom = `${player.bottom - seekRect.top + 8}px`
    this.stampTarget.textContent = clock(time)
  }

  hide() {
    this.thumbTarget.hidden = true
    this._wanted = null
    this.seekTarget.style.removeProperty("--h")
  }

  // Draw from cache, else ask the hidden video; only the newest wanted bucket is ever decoded.
  want(bucket) {
    this._wanted = bucket
    const cached = this._cache.get(bucket) || this._coarse.get(bucket)
    if (cached) return this.draw(cached, true)
    this.drawNearest(bucket) // never a blank thumbnail while the exact frame decodes (dimmed: it is not this time yet)
    this.ensureProbe()
    this.pump()
  }

  ensureProbe() {
    if (this._probe) return
    const probe = document.createElement("video")
    probe.muted = true
    probe.preload = "metadata"
    probe.playsInline = true
    probe.hidden = true
    probe.src = this.videoTarget.currentSrc || this.videoTarget.src
    probe.addEventListener("seeked", () => this.seeked())
    probe.addEventListener("loadedmetadata", () => { this.planCoarse(); this.pump() })
    this.element.appendChild(probe)
    this._probe = probe
  }

  // The hovered bucket always goes first; with nothing wanted the probe works through the coarse frames.
  pump() {
    const probe = this._probe
    if (!probe || probe.readyState < 1 || this._seeking != null) return
    let target = this._wanted
    if (target == null || this._cache.has(target) || this._coarse.has(target)) {
      if (!this._todo?.length) return
      target = this._todo.shift()
      this._fill = true
    } else this._fill = false
    this._seeking = target
    probe.currentTime = target
  }

  // Idle-time prefill: evenly spaced bucket times, started only after the first hover and only while nothing is wanted.
  planCoarse() {
    const duration = this.videoTarget.duration
    if (!(duration > 0)) return
    const step = bucketStep(duration)
    this._todo = Array.from({ length: COARSE }, (_, i) => bucketTime(((i + 0.5) / COARSE) * duration, step))
  }

  seeked() {
    const bucket = this._seeking
    this._seeking = null
    if (bucket == null || !this._probe) return
    const frame = document.createElement("canvas")
    frame.width = this.canvasTarget.width
    frame.height = this.canvasTarget.height
    try { frame.getContext("2d").drawImage(this._probe, 0, 0, frame.width, frame.height) } catch { return }
    if (this._fill) this._coarse.set(bucket, frame)
    else {
      this._cache.set(bucket, frame)
      if (this._cache.size > CACHE_MAX) this._cache.delete(this._cache.keys().next().value)
    }
    if (bucket === this._wanted) this.draw(frame, true)
    else if (this._wanted != null && !this._cache.has(this._wanted) && !this._coarse.has(this._wanted)) this.pump()
    else this.idle(() => this.pump())
  }

  idle(fn) {
    const run = () => { if (this._probe) fn() }
    if (window.requestIdleCallback) window.requestIdleCallback(run, { timeout: 500 })
    else setTimeout(run, 50)
  }

  drawNearest(bucket) {
    let best = null
    for (const map of [this._cache, this._coarse]) {
      for (const [key, frame] of map) if (best == null || Math.abs(key - bucket) < Math.abs(best.key - bucket)) best = { key, frame }
    }
    if (best) this.draw(best.frame, false)
    else this.thumbTarget.toggleAttribute("data-stale", true)
  }

  // exact: the frame belongs to the time under the cursor. Otherwise it is the nearest known one and shown dimmed.
  draw(frame, exact) {
    const canvas = this.canvasTarget
    canvas.getContext("2d").drawImage(frame, 0, 0, canvas.width, canvas.height)
    this.thumbTarget.toggleAttribute("data-stale", !exact)
  }

  // Source changed or controller leaving: release the hidden video's connection and decoder.
  reset() {
    if (this._probe) {
      this._probe.removeAttribute("src")
      this._probe.load()
      this._probe.remove()
    }
    this._probe = null
    this._seeking = null
    this._wanted = null
    this._todo = null
    this._cache?.clear()
    this._coarse?.clear()
    if (this.hasThumbTarget) this.thumbTarget.hidden = true
  }
}
