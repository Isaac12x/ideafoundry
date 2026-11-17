import { Controller } from "@hotwired/stimulus"
import { binding, matches } from "lib/shortcut_bindings"

// Voice mode everywhere: one floating mic follows the focused text field. Audio is captured here, encoded to
// 16 kHz mono WAV, POSTed to /transcriptions (Rails proxies the local audio service) and the formatted text is
// inserted at the caret. Attached to <body> by the layout.
const TEXT_INPUTS = ["text", "search", "url", "email", "tel"]
const RATE = 16000
const MIN_SECONDS = 1
const MAX_SECONDS = 300
const MIC = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>'

function eligible(el) {
  if (!(el instanceof HTMLElement) || el.closest("[data-voice='off'], .typing-lock-page, .voice-dictation")) return false
  if (el instanceof HTMLTextAreaElement) return !el.readOnly && !el.disabled
  if (el instanceof HTMLInputElement) return TEXT_INPUTS.includes(el.type) && !el.readOnly && !el.disabled
  return el.isContentEditable
}

// Float32 chunks at the mic's rate -> 16-bit PCM WAV at 16 kHz mono (box-filter downsample).
function encodeWav(chunks, inRate) {
  const input = new Float32Array(chunks.reduce((n, c) => n + c.length, 0))
  let at = 0
  chunks.forEach((c) => { input.set(c, at); at += c.length })
  const ratio = inRate / RATE
  const n = Math.floor(input.length / ratio)
  const view = new DataView(new ArrayBuffer(44 + n * 2))
  const str = (o, s) => [...s].forEach((ch, i) => view.setUint8(o + i, ch.charCodeAt(0)))
  str(0, "RIFF"); view.setUint32(4, 36 + n * 2, true); str(8, "WAVEfmt ")
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true)
  view.setUint32(24, RATE, true); view.setUint32(28, RATE * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true)
  str(36, "data"); view.setUint32(40, n * 2, true)
  for (let i = 0; i < n; i++) {
    const from = Math.floor(i * ratio)
    const to = Math.max(from + 1, Math.floor((i + 1) * ratio))
    let sum = 0
    for (let j = from; j < to; j++) sum += input[j]
    const s = Math.max(-1, Math.min(1, sum / (to - from)))
    view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true)
  }
  return { blob: new Blob([view], { type: "audio/wav" }), seconds: n / RATE }
}

export default class extends Controller {
  connect() {
    this.state = "idle"
    this.field = null
    this.build()
    this.on(document, "focusin", (e) => this.focused(e.target))
    this.on(document, "focusout", () => setTimeout(() => this.blurred(), 0))
    this.on(document, "keydown", (e) => this.keydown(e), true)
    this.on(window, "scroll", () => this.place(), true)
    this.on(window, "resize", () => this.place())
    this.focused(document.activeElement)
  }

  disconnect() {
    this.teardownAudio()
    clearTimeout(this.hintTimer)
    this.listeners.forEach(([t, ...args]) => t.removeEventListener(...args))
    this.root.remove()
  }

  on(target, type, fn, capture = false) {
    target.addEventListener(type, fn, capture)
    ;(this.listeners ||= []).push([target, type, fn, capture])
  }

  build() {
    this.root = document.createElement("div")
    this.root.className = "voice-dictation"
    this.root.hidden = true
    this.root.innerHTML = '<span class="voice-dictation__hint" role="status" aria-live="polite"></span>' +
      `<button type="button" class="voice-dictation__btn" aria-pressed="false" aria-label="Dictate" title="Dictate">${MIC}</button>`
    this.hint = this.root.firstChild
    this.btn = this.root.lastChild
    // mousedown must not steal focus from the field being dictated into
    this.btn.addEventListener("mousedown", (e) => e.preventDefault())
    this.btn.addEventListener("click", () => this.toggle())
    document.body.appendChild(this.root)
  }

  focused(el) {
    if (!eligible(el)) return
    this.field = el.closest("trix-editor") || el
    this.place()
  }

  blurred() {
    if (this.state !== "idle") return
    if (eligible(document.activeElement)) return
    this.field = null
    this.root.hidden = true
  }

  place() {
    if (!this.field?.isConnected) return this.field && this.state === "idle" ? this.blurred() : null
    const r = this.field.getBoundingClientRect()
    const off = r.bottom < 0 || r.top > innerHeight
    this.root.hidden = off && this.state === "idle"
    const top = r.height < 44 ? r.top + (r.height - 28) / 2 : r.bottom - 28 - 6
    this.root.style.top = `${Math.max(4, Math.min(innerHeight - 32, top))}px`
    this.root.style.right = `${Math.max(4, innerWidth - r.right + 6)}px`
  }

  keydown(e) {
    if (e.key === "Escape" && this.state === "recording") {
      e.preventDefault(); e.stopImmediatePropagation()
      return this.cancel()
    }
    if (!matches(binding("dictate"), e)) return
    if (this.state === "idle" && !eligible(document.activeElement)) return
    e.preventDefault()
    this.toggle()
  }

  toggle() {
    if (this.state === "recording") this.finish()
    else if (this.state === "idle" && this.field) this.start()
  }

  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      return this.say("Microphone blocked", true)
    }
    const ctx = (this.ctx = new (window.AudioContext || window.webkitAudioContext)())
    this.chunks = []
    this.rate = ctx.sampleRate
    const source = ctx.createMediaStreamSource(this.stream)
    // ponytail: ScriptProcessor is deprecated but universal; move to AudioWorklet if it is ever removed
    this.proc = ctx.createScriptProcessor(4096, 1, 1)
    this.proc.onaudioprocess = (e) => {
      const data = new Float32Array(e.inputBuffer.getChannelData(0))
      this.chunks.push(data)
      let sum = 0
      for (let i = 0; i < data.length; i += 8) sum += data[i] * data[i]
      this.btn.style.setProperty("--level", Math.min(1, Math.sqrt(sum / (data.length / 8)) * 6).toFixed(2))
    }
    source.connect(this.proc)
    this.proc.connect(ctx.destination)
    this.startedAt = Date.now()
    this.setState("recording")
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  tick() {
    const s = Math.floor((Date.now() - this.startedAt) / 1000)
    this.hint.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
    if (s >= MAX_SECONDS) this.finish()
  }

  teardownAudio() {
    clearInterval(this.timer)
    this.proc?.disconnect()
    this.stream?.getTracks().forEach((t) => t.stop())
    this.ctx?.close().catch(() => {})
    this.proc = this.stream = this.ctx = null
  }

  cancel() {
    this.teardownAudio()
    this.chunks = []
    this.setState("idle")
    this.hint.textContent = ""
    this.field?.focus()
  }

  async finish() {
    const chunks = this.chunks
    this.teardownAudio()
    const { blob, seconds } = encodeWav(chunks, this.rate)
    if (seconds < MIN_SECONDS) return this.say("Hold a bit longer", false)
    this.setState("processing")
    this.hint.textContent = "Formatting…"
    try {
      const res = await fetch("/transcriptions", {
        method: "POST",
        headers: { "Content-Type": "audio/wav", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" },
        body: blob,
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) return this.say(data.error || "Transcription failed", true)
      if (!data.text) return this.say("Heard nothing", false)
      this.insert(data.text)
      this.say("", false)
    } catch {
      this.say("Network error", true)
    }
  }

  insert(text) {
    const el = this.field
    if (!el?.isConnected) return this.say("Field is gone", true)
    el.focus()
    if (el.tagName === "TRIX-EDITOR") {
      el.editor.insertString(text)
    } else if ("value" in el) {
      const value = el.value
      let start = el.selectionStart
      let end = el.selectionEnd
      if (start == null) start = end = value.length // email inputs expose no caret
      const lead = start > 0 && !/\s/.test(value[start - 1]) ? " " : ""
      el.value = value.slice(0, start) + lead + text + value.slice(end)
      const caret = start + lead.length + text.length
      try { el.setSelectionRange(caret, caret) } catch { /* no selection API for this type */ }
      el.dispatchEvent(new Event("input", { bubbles: true }))
      el.dispatchEvent(new Event("change", { bubbles: true }))
    } else {
      document.execCommand("insertText", false, text)
    }
  }

  say(message, isError) {
    this.setState(isError ? "error" : "idle")
    this.hint.textContent = message
    clearTimeout(this.hintTimer)
    this.hintTimer = setTimeout(() => {
      if (this.state === "error") this.setState("idle")
      if (this.state === "idle") { this.hint.textContent = ""; this.blurred() }
    }, 4000)
  }

  setState(state) {
    this.state = state
    this.root.dataset.state = state
    const rec = state === "recording"
    this.btn.setAttribute("aria-pressed", String(rec))
    this.btn.setAttribute("aria-label", rec ? "Stop dictation" : "Dictate")
    this.btn.title = rec ? "Stop (Esc cancels)" : "Dictate"
    this.btn.disabled = state === "processing"
    if (!rec) this.btn.style.removeProperty("--level")
    this.place()
  }
}
