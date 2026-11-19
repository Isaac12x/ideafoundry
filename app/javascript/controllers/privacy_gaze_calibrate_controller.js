import { Controller } from "@hotwired/stimulus"

// Settings panel: look at the middle of the screen for ~2s to store this device's baseline (camera sits above the
// screen, so "looking" is never yaw/pitch 0). Also a live Looking/Away test.
const WARMUP_MS = 700
const SAMPLE_MS = 2000
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }

export default class extends Controller {
  static targets = ["button", "status", "preview", "live", "message"]

  connect() { this.gone = false; this.showStatus() }
  disconnect() { this.gone = true; this.stop() }

  async toggle() {
    if (this.session) return this.stop()
    const a = assets()
    if (!a) return this.say("Gaze assets missing")
    this.buttonTarget.disabled = true
    this.say("Starting camera…")
    try {
      this.lib ??= await import(a.bundle)
      if (this.gone) return
      this.baseline = this.lib.loadBaseline()
      this.samples = []
      this.t0 = null
      this.done = false
      this.session = await this.lib.startGazeSession({
        assets: a,
        video: this.previewTarget,
        onSample: (f, now) => this.sample(f, now),
        onError: () => { this.stop(); this.say("Camera unavailable") }
      })
      if (this.gone) return this.stop()
    } catch {
      this.say("Camera unavailable")
    }
    this.buttonTarget.disabled = false
    if (this.session) {
      this.previewTarget.hidden = false
      this.buttonTarget.textContent = "Stop"
      this.say("Look at the middle of the screen…")
    }
  }

  sample(f, now) {
    const looking = this.lib.isLooking(f, this.baseline)
    this.liveTarget.textContent = looking ? "Looking" : "Away"
    this.liveTarget.dataset.looking = looking
    this.t0 ??= now
    if (this.done) return
    if (now - this.t0 < WARMUP_MS) return
    if (f) this.samples.push(f)
    if (now - this.t0 >= WARMUP_MS + SAMPLE_MS) this.finish()
  }

  finish() {
    this.done = true
    const b = this.lib.calibrate(this.samples)
    if (b && this.samples.length >= 5 && this.lib.saveBaseline(b)) {
      this.baseline = b
      window.dispatchEvent(new CustomEvent("privacy-gaze:calibrated"))
      this.say("Calibrated. Look away to test.")
    } else {
      this.say("No face seen. Try again.")
    }
    this.showStatus()
  }

  stop() {
    this.session?.stop()
    this.session = null
    this.done = false
    if (this.hasPreviewTarget) this.previewTarget.hidden = true
    if (this.hasButtonTarget) { this.buttonTarget.textContent = "Calibrate"; this.buttonTarget.disabled = false }
    if (this.hasLiveTarget) this.liveTarget.textContent = ""
  }

  showStatus() {
    if (!this.hasStatusTarget) return
    // the bundle may not be loaded yet, so read the key directly (same key as gaze_state.js)
    let ok = false
    try { ok = !!localStorage.getItem("privacy-gaze:baseline") } catch {}
    this.statusTarget.textContent = ok ? "Calibrated" : "Not calibrated"
  }

  say(t) { if (this.hasMessageTarget) this.messageTarget.textContent = t }
}
