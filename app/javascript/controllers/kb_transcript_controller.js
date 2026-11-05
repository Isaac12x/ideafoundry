import { Controller } from "@hotwired/stimulus"

// Selectable transcript under an audio/video player: lines carry timestamps,
// clicking a line (without selecting text) seeks, the current line follows
// playback. Cues come from the sidecar .vtt / downloaded captions; "Transcribe"
// runs local whisper in a background job and is polled until it lands.
export default class extends Controller {
  static targets = ["media", "list", "status", "button"]
  static values = { url: String }

  connect() {
    this.cues = []
    this.active = -1
    this.load()
  }

  disconnect() {
    window.clearTimeout(this.timer)
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
      text.textContent = cue.text
      row.append(time, text)
      return row
    }))
    this.listTarget.hidden = false
    this.highlight()
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
    this.mediaTarget.currentTime = cue.start
    this.mediaTarget.play?.()
  }

  highlight() {
    if (!this.cues.length || !this.hasMediaTarget) return
    const index = activeIndex(this.cues, this.mediaTarget.currentTime)
    if (index === this.active) return
    const rows = this.listTarget.children
    rows[this.active]?.classList.remove("is-active")
    rows[this.active]?.removeAttribute("aria-current")
    this.active = index
    const row = rows[index]
    if (!row) return
    row.classList.add("is-active")
    row.setAttribute("aria-current", "true")
    const list = this.listTarget
    if (row.offsetTop < list.scrollTop || row.offsetTop + row.offsetHeight > list.scrollTop + list.clientHeight) {
      list.scrollTop = row.offsetTop - list.clientHeight / 3
    }
  }

  say(message) {
    this.statusTarget.textContent = message
  }
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
  return found // ponytail: gaps between cues keep the last line lit
}

function formatTime(seconds) {
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = String(total % 60).padStart(2, "0")
  return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`
}
