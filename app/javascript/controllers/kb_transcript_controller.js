import { Controller } from "@hotwired/stimulus"

const IDLE_MS = 2500 // after a manual scroll, auto-centering resumes once the list has been left alone this long

// Selectable transcript under an audio/video player: lines carry timestamps,
// clicking a line (without selecting text) seeks. Karaoke style: the current
// line stays centered and its words fill with the accent as the media plays
// (rAF while playing, so it is smooth between coarse timeupdate events).
// Cues come from the sidecar .vtt / downloaded captions; "Transcribe" runs
// local whisper in a background job and is polled until it lands.
export default class extends Controller {
  static targets = ["media", "list", "status", "button"]
  static values = { url: String }

  connect() {
    this.cues = []
    this.active = -1
    // collapsed/hidden panels have no height; recenter when the list gets (or changes) size
    if (window.ResizeObserver) {
      this.resizer = new window.ResizeObserver(() => { if (Date.now() - (this.userAt || 0) > IDLE_MS) this.recenter("auto") })
      this.resizer.observe(this.listTarget)
    }
    this.load()
  }

  disconnect() {
    window.clearTimeout(this.timer)
    window.clearTimeout(this.idle)
    this.resizer?.disconnect()
    this.stop()
    this.gone = true
  }

  async load() {
    if (this.gone) return
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) throw new Error("transcript request failed")
      this.show(await response.json())
    } catch {
      this.say("Transcript could not be loaded.")
    }
  }

  show(data) {
    this.buttonTarget.hidden = !data.can_transcribe
    this.buttonTarget.textContent = data.status === "ready" ? "Transcribe locally (finer timing)" : "Transcribe"
    if (data.running) {
      this.timer = window.setTimeout(() => this.load(), 3000)
    }
    if (data.status === "ready") {
      const fresh = JSON.stringify(data.cues) !== JSON.stringify(this.cues)
      this.cues = data.cues
      if (fresh) this.render()
      this.say(data.running ? "Transcribing locally…" : "")
    } else {
      this.say({ running: "Transcribing locally…", failed: data.error || "Transcription failed.", none: "No transcript yet." }[data.status] || "")
    }
  }

  render() {
    this.active = -1
    this.listTarget.replaceChildren(...this.cues.map((cue, index) => {
      const row = document.createElement("li")
      row.className = "kb-cue"
      row.dataset.index = index
      row.dataset.action = "click->kb-transcript#seek keydown.enter->kb-transcript#seek keydown.space->kb-transcript#seek"
      row.tabIndex = 0
      row.setAttribute("role", "button")
      row.setAttribute("aria-label", `${formatTime(cue.start)} ${cue.text}`)
      const time = document.createElement("span")
      time.className = "kb-cue__time"
      time.textContent = formatTime(cue.start)
      time.setAttribute("aria-hidden", "true")
      const text = document.createElement("span")
      text.className = "kb-cue__text"
      // words in spans (--p = fill 0..1), whitespace as plain text so copy stays contiguous
      text.append(...cue.text.split(/(\s+)/).map((part) => {
        if (!part || /^\s+$/.test(part)) return part
        const word = document.createElement("span")
        word.className = "kb-cue__w"
        word.textContent = part
        return word
      }))
      row.append(time, text)
      return row
    }))
    this.listTarget.hidden = false
    this.words = []
    this.highlight()
    if (this.hasMediaTarget && !this.mediaTarget.paused) this.follow() // already playing when cues landed
  }

  async transcribe() {
    this.buttonTarget.hidden = true
    this.say("Transcribing locally…")
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        credentials: "same-origin"
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "Could not start transcription.")
      this.show(data)
    } catch (error) {
      this.say(error.message)
      this.buttonTarget.hidden = false
    }
  }

  seek(event) {
    if (event.type === "keydown") event.preventDefault() // space would scroll
    else if (!window.getSelection().isCollapsed) return // dragging to copy text, not seeking

    const cue = this.cues[Number(event.currentTarget.dataset.index)]
    if (!cue || !this.hasMediaTarget) return
    this.userAt = 0 // a seek always recenters, even right after a manual scroll
    this.jump = true
    if (cue === this.cues[this.active]) { this.jump = false; this.recenter("auto") } // already the active cue: highlight() won't move
    this.mediaTarget.currentTime = cue.start
    this.mediaTarget.play?.()
  }

  // play -> start the fill loop; pause/ended -> stop it (timeupdate/seeked still repaint once)
  follow() {
    if (this.frame || this.gone) return
    const step = () => {
      this.highlight()
      this.frame = this.mediaTarget.paused || this.mediaTarget.ended ? null : window.requestAnimationFrame(step)
    }
    this.frame = window.requestAnimationFrame(step)
  }

  stop() {
    if (this.frame) window.cancelAnimationFrame(this.frame)
    this.frame = null
  }

  // wheel/touch on the list: leave the scroll position alone until it has been idle, then recenter
  userScrolled() {
    this.userAt = Date.now()
    window.clearTimeout(this.idle)
    this.idle = window.setTimeout(() => this.recenter("smooth"), IDLE_MS)
  }

  highlight() {
    if (!this.cues.length || !this.hasMediaTarget) return
    const time = this.mediaTarget.currentTime
    let index = activeIndex(this.cues, time)
    if (index >= 0 && time > cueEnd(this.cues, index)) index = -1 // finished and nothing started yet: nothing lit
    if (index === this.active) return this.paint(time)
    const rows = this.listTarget.children
    rows[this.active]?.classList.remove("is-active")
    rows[this.active]?.removeAttribute("aria-current")
    const far = this.jump || Math.abs(index - this.active) > 1
    this.jump = false
    this.active = index
    this.words = []
    const row = rows[index]
    if (!row) return
    row.classList.add("is-active")
    row.setAttribute("aria-current", "true")
    this.words = [...(row.querySelectorAll?.(".kb-cue__w") || [])]
    this.paint(time)
    if (Date.now() - (this.userAt || 0) > IDLE_MS) this.recenter(far ? "auto" : "smooth")
  }

  // active cue vertically centered in the list (container scroll only; scrollIntoView would move the page)
  recenter(behavior) {
    const list = this.listTarget
    const row = list.children[this.active]
    if (!row || !list.clientHeight) return
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    list.scrollTo?.({ top: row.offsetTop - (list.clientHeight - row.offsetHeight) / 2, behavior: reduced ? "auto" : behavior })
  }

  paint(time) {
    if (!this.words?.length) return
    const fill = wordFill(this.words.map((w) => w.textContent.length), cueProgress(this.cues, this.active, time))
    this.words.forEach((w, i) => {
      if (w.dataset.p !== String(fill[i])) { w.dataset.p = fill[i]; w.style.setProperty("--p", fill[i]) } // skip unchanged writes
    })
  }

  say(message) {
    this.statusTarget.textContent = message
  }
}

// When the cue stops: its end, else the next cue's start, else 5s.
function cueEnd(cues, index) {
  const cue = cues[index]
  return cue.end > cue.start ? cue.end : (cues[index + 1]?.start ?? cue.start + 5)
}

// 0..1 through the cue at `time`.
function cueProgress(cues, index, time) {
  const start = cues[index].start
  return Math.min(1, Math.max(0, (time - start) / Math.max(cueEnd(cues, index) - start, 0.001)))
}

// Per-word fill 0..1 for `progress` through the whole line, words weighted by length.
function wordFill(lengths, progress) {
  const target = progress * lengths.reduce((a, b) => a + b, 0)
  let before = 0
  return lengths.map((len) => {
    const fill = Math.min(1, Math.max(0, (target - before) / len))
    before += len
    return fill
  })
}

// Index of the cue playing at `time` (last cue that has started), -1 before the first.
function activeIndex(cues, time) {
  let low = 0
  let high = cues.length - 1
  let found = -1
  while (low <= high) {
    const mid = (low + high) >> 1
    if (cues[mid].start <= time) { found = mid; low = mid + 1 } else { high = mid - 1 }
  }
  return found
}

function formatTime(seconds) {
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = String(total % 60).padStart(2, "0")
  return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`
}
