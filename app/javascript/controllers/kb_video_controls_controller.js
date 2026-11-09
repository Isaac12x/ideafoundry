import { Controller } from "@hotwired/stimulus"
import { inverseScale, clock } from "lib/kb_zoom"

// Modifier that lets video keys work from inside a notes field: Ctrl or Option on Mac (Option+Arrow then seeks
// instead of word-jumping); Ctrl alone is select/edit shortcuts elsewhere, so Ctrl+Alt.
const MAC = /mac/i.test(navigator.platform)
const NOTES_MODIFIER = MAC ? "Ctrl or Option" : "Ctrl+Alt"

// Custom control bar for KB video (native controls scale with browser/pinch zoom). The <video> stays the
// element every other KB controller reads (transcript, note stamps, screenshots, resume, editor).
// Fullscreen takes the wrapper so the bar stays visible. Keys apply while focus is inside the player.
export default class extends Controller {
  static targets = ["video", "play", "seek", "time", "mute", "volume", "speed", "captions", "fullscreen"]

  connect() {
    this._off = []
    const video = this.videoTarget
    for (const type of ["timeupdate", "durationchange", "loadedmetadata", "play", "pause", "ended", "volumechange", "ratechange"]) {
      this.listen(video, type, () => this.sync())
    }
    this.listen(document, "fullscreenchange", () => this.sync())
    this.listen(document, "keydown", (event) => this.noteKey(event))
    this.element.querySelector(".kb-vplayer__bar")?.setAttribute("title", `While typing in notes, hold ${NOTES_MODIFIER} with a shortcut key to control the video`)
    for (const type of ["pointerup", "pointercancel"]) this.listen(document, type, () => { this._scrubbing = false })
    this.listen(window, "resize", () => this.zoom())
    if (window.visualViewport) this.listen(window.visualViewport, "resize", () => this.zoom())
    if (this.hasCaptionsTarget) this.captionsTarget.hidden = !video.querySelector("track")
    this.zoom()
    this.sync()
  }

  disconnect() {
    this._off.forEach((off) => off())
    if (document.fullscreenElement === this.element) document.exitFullscreen?.().catch(() => {})
  }

  listen(target, type, handler) {
    target.addEventListener(type, handler)
    this._off.push(() => target.removeEventListener(type, handler))
  }

  zoom() {
    this.element.style.setProperty("--kb-vinv", inverseScale(window.devicePixelRatio || 1, undefined, window.visualViewport?.scale || 1))
  }

  toggle() {
    const video = this.videoTarget
    if (video.paused || video.ended) video.play().catch(() => {})
    else video.pause()
  }

  // Dragging only moves the thumb and time label (the preview shows the frame); the video seeks on release.
  scrub() {
    this._scrubbing = true
    this.timeTarget.textContent = `${clock(Number(this.seekTarget.value))} / ${clock(this.videoTarget.duration)}`
    this.fill()
  }

  // Played portion for the custom track (--p); the preview controller drives the hover ghost (--h).
  fill() {
    const max = Number(this.seekTarget.max)
    this.seekTarget.style.setProperty("--p", max > 0 ? `${(Number(this.seekTarget.value) / max) * 100}%` : "0%")
  }

  seek() {
    this._scrubbing = false
    this.videoTarget.currentTime = Number(this.seekTarget.value)
  }

  skip(seconds) { this.videoTarget.currentTime = Math.max(0, this.videoTarget.currentTime + seconds) }

  volume() {
    this.videoTarget.volume = Number(this.volumeTarget.value)
    this.videoTarget.muted = false
  }

  mute() { this.videoTarget.muted = !this.videoTarget.muted }

  speed() { this.videoTarget.playbackRate = Number(this.speedTarget.value) }

  captions() {
    const track = this.videoTarget.textTracks[0]
    if (track) track.mode = track.mode === "showing" ? "hidden" : "showing"
    this.sync()
  }

  fullscreen() {
    if (document.fullscreenElement) document.exitFullscreen()
    else this.element.requestFullscreen?.().catch(() => {})
  }

  key(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const tag = event.target.tagName
    if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA" || (tag === "BUTTON" && event.key === " ")) return
    this.run(event)
  }

  // Focus in a notes field: only the notes modifier combo reaches the video.
  noteKey(event) {
    if (!event.target.closest?.(".kb-notes-editor-body, .kb-note__form") || event.metaKey) return
    if (MAC ? !(event.ctrlKey || event.altKey) : !(event.ctrlKey && event.altKey)) return
    this.run(event)
  }

  run(event) {
    const actions = {
      " ": () => this.toggle(),
      arrowleft: () => this.skip(-5),
      arrowright: () => this.skip(5),
      m: () => this.mute(),
      f: () => this.fullscreen()
    }
    const action = actions[event.key.toLowerCase()]
    if (!action) return
    event.preventDefault()
    action()
  }

  sync() {
    const video = this.videoTarget
    const playing = !video.paused && !video.ended
    this.element.classList.toggle("is-playing", playing)
    this.label(this.playTarget, playing ? "Pause" : "Play", "Space")
    const duration = Number.isFinite(video.duration) ? video.duration : 0
    this.seekTarget.max = duration
    if (!this._scrubbing) this.seekTarget.value = video.currentTime
    this.fill()
    this.seekTarget.setAttribute("aria-valuetext", `${clock(video.currentTime)} of ${clock(duration)}`)
    if (!this._scrubbing) this.timeTarget.textContent = `${clock(video.currentTime)} / ${clock(duration)}`
    const muted = video.muted || video.volume === 0
    this.element.classList.toggle("is-muted", muted)
    this.label(this.muteTarget, muted ? "Unmute" : "Mute", "M")
    this.volumeTarget.value = video.muted ? 0 : video.volume
    if (this.speedTarget.value !== String(video.playbackRate)) this.speedTarget.value = String(video.playbackRate)
    if (this.hasCaptionsTarget) this.captionsTarget.setAttribute("aria-pressed", String(video.textTracks[0]?.mode === "showing"))
    const fullscreen = document.fullscreenElement === this.element
    this.element.classList.toggle("is-fullscreen", fullscreen)
    this.label(this.fullscreenTarget, fullscreen ? "Exit fullscreen" : "Fullscreen", "F")
  }

  label(button, name, key) {
    button.setAttribute("aria-label", name)
    button.title = `${name} (${key})`
  }
}
