import { Controller } from "@hotwired/stimulus"

// Remembers where you left off in a KB file and restores it on open:
// playback time on <video>/<audio>, scroll offset on documents.
// Keyed per file in localStorage ("kb-resume:<src>:<rel>").
export default class extends Controller {
  static values = { key: String }

  connect() {
    this._key = `kb-resume:${this.keyValue}`
    const saved = parseFloat(localStorage.getItem(this._key) || "0")

    if (this.element.matches("video, audio")) {
      this._media = this.element
      // Adopted across a frame swap (lib/kb_video_swap): it already sits at this file's position, do not seek again.
      if (saved > 0 && this._media.dataset.kbSwapKey !== this.keyValue) this._restore(saved)
      this._onSwap = (event) => this._swap(event.detail)
      this._media.addEventListener("kb-video:swap", this._onSwap)
      this._onRelease = () => this._release()
      this._media.addEventListener("kb-video:release", this._onRelease)
      this._listen()
    } else {
      this._scroller = this.element.closest(".kb-content-area")
      if (!this._scroller) return
      this._scroller.scrollTop = saved
      this._onScroll = this._throttled(() => this._store(this._scroller.scrollTop))
      this._scroller.addEventListener("scroll", this._onScroll)
    }
  }

  disconnect() {
    if (this._media?.isConnected) {
      // Moved, not removed (the frame swap keeps the live player): keep playing, just drop our listeners.
      this._unlisten()
      this._media.removeEventListener("kb-video:swap", this._onSwap)
      this._media.removeEventListener("kb-video:release", this._onRelease)
      return
    }
    this._release()
    // Scroll case saves only from real scroll events: by disconnect time the
    // container may already hold (and have clamped to) the next document.
    if (this._scroller && this._onScroll) {
      this._scroller.removeEventListener("scroll", this._onScroll)
    }
  }

  // Leaving: stop buffering at once instead of waiting for GC to drop the connection and decoder.
  // Also fired by a tree click on a project (no video swap there), so the stream stops before the page request waits behind it.
  _release() {
    if (!this._media || this._released) return
    this._released = true
    this._store(this._media.currentTime)
    this._unlisten()
    this._media.pause()
    this._media.removeAttribute("src")
    this._media.querySelectorAll("source").forEach((source) => source.remove())
    this._media.load()
  }

  _listen() {
    this._onTick = this._throttled(() => this._store(this._media.currentTime))
    this._media.addEventListener("timeupdate", this._onTick)
    this._media.addEventListener("pause", this._onTick.now)
    this._media.addEventListener("ended", this._onTick.now)
  }

  _unlisten() {
    this._media.removeEventListener("timeupdate", this._onTick)
    this._media.removeEventListener("pause", this._onTick.now)
    this._media.removeEventListener("ended", this._onTick.now)
  }

  // The saved position only counts once applied: until then the element sits at 0 and must not overwrite it.
  // The flag lives on the element: an adopted player is read by a new controller instance. A newer restore/swap voids an older one.
  _restore(saved) {
    const media = this._media
    const seq = media._resumeSeq = (media._resumeSeq || 0) + 1
    media._resumePending = true
    this._whenSeekable(() => {
      if (media._resumeSeq !== seq) return
      media.currentTime = saved
      media._resumePending = false
    })
  }

  // Tree click on another video: remember where this one was, then re-point the same element at the next file.
  // detail.undo puts the old file back (the new one never loaded: deleted, renamed, offline).
  _swap(detail) {
    const { url, key } = detail
    const media = this._media
    const playing = !media.paused && !media.ended
    const before = { key: this.keyValue, swapKey: media.dataset.kbSwapKey, src: media.getAttribute("src"), sources: Array.from(media.querySelectorAll("source")), time: media.currentTime }
    detail.undo = () => this._unswap(before, playing)
    this._store(media.currentTime)
    this._unlisten()
    this.keyValue = key
    this._key = `kb-resume:${key}`
    media.dataset.kbSwapKey = key
    media.querySelectorAll("source").forEach((source) => source.remove())
    media.src = url
    media.load()
    const saved = parseFloat(localStorage.getItem(this._key) || "0")
    if (saved > 0) this._restore(saved)
    else { media._resumeSeq = (media._resumeSeq || 0) + 1; media._resumePending = false }
    this._listen()
    if (playing) media.play().catch(() => {})
  }

  _unswap(before, playing) {
    const media = this._media
    if (!media?.isConnected || this.keyValue === before.key) return
    this._unlisten()
    this.keyValue = before.key
    this._key = `kb-resume:${before.key}`
    if (before.swapKey === undefined) delete media.dataset.kbSwapKey
    else media.dataset.kbSwapKey = before.swapKey
    media.querySelectorAll("source").forEach((source) => source.remove())
    if (before.src) media.setAttribute("src", before.src)
    else media.removeAttribute("src")
    before.sources.forEach((source) => media.append(source))
    media.load()
    if (before.time > 0) this._restore(before.time)
    else { media._resumeSeq = (media._resumeSeq || 0) + 1; media._resumePending = false }
    this._listen()
    if (playing) media.play().catch(() => {})
  }

  _whenSeekable(fn) {
    if (this.element.readyState >= 1) fn()
    else this.element.addEventListener("loadedmetadata", fn, { once: true })
  }

  _store(pos) {
    if (this._media?._resumePending || !Number.isFinite(pos)) return
    // A file watched/read to the end restarts from the top next time.
    if (this._media?.ended) pos = 0
    localStorage.setItem(this._key, String(pos))
  }

  _throttled(fn, ms = 1000) {
    let last = 0
    let timer
    const run = () => {
      last = Date.now()
      clearTimeout(timer)
      fn()
    }
    const throttled = () => {
      const wait = last + ms - Date.now()
      if (wait <= 0) run()
      else {
        clearTimeout(timer)
        timer = setTimeout(run, wait)
      }
    }
    throttled.now = run
    return throttled
  }
}
