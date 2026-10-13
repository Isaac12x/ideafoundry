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
      if (saved > 0) this._whenSeekable(() => { this._media.currentTime = saved })
      this._onTick = this._throttled(() => this._store(this._media.currentTime))
      this._media.addEventListener("timeupdate", this._onTick)
      this._media.addEventListener("pause", this._onTick.now)
      this._media.addEventListener("ended", this._onTick.now)
    } else {
      this._scroller = this.element.closest(".kb-content-area")
      if (!this._scroller) return
      this._scroller.scrollTop = saved
      this._onScroll = this._throttled(() => this._store(this._scroller.scrollTop))
      this._scroller.addEventListener("scroll", this._onScroll)
    }
  }

  disconnect() {
    if (this._media) this._store(this._media.currentTime)
    // Scroll case saves only from real scroll events: by disconnect time the
    // container may already hold (and have clamped to) the next document.
    if (this._scroller && this._onScroll) {
      this._scroller.removeEventListener("scroll", this._onScroll)
    }
  }

  _whenSeekable(fn) {
    if (this.element.readyState >= 1) fn()
    else this.element.addEventListener("loadedmetadata", fn, { once: true })
  }

  _store(pos) {
    if (!Number.isFinite(pos)) return
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
