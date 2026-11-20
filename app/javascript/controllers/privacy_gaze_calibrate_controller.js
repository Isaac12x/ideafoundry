import { Controller } from "@hotwired/stimulus"

// Settings panel: look at the middle of the screen for ~2s to store this device's baseline (camera sits above the
// screen, so "looking" is never yaw/pitch 0). Also a live Looking/Away test.
const WARMUP_MS = 700
const SAMPLE_MS = 2000
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }

const SAMPLES = 5 // face descriptors stored per enrollment
const CAPTURE_MS = 400
const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content
const call = (url, method, body) => fetch(url, {
  method, credentials: "same-origin",
  headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf() },
  body: body && JSON.stringify(body),
}).then(async (r) => ({ ok: r.ok, data: await r.json().catch(() => ({})) }))

export default class extends Controller {
  static targets = ["button", "status", "preview", "live", "message",
    "enrollButton", "enrollStatus", "enrollStage", "enrollPreview", "enrollMessage", "enrollSteps", "check", "removeButton"]
  static values = { faceUrl: String }

  connect() { this.gone = false; this.showStatus(); this.loadFace() }
  disconnect() { this.gone = true; this.stop(); this.stopEnroll() }

  // ---- face ID enrollment ----
  async loadFace() {
    if (!this.hasEnrollStatusTarget || !this.faceUrlValue) return
    try {
      const { ok, data } = await call(this.faceUrlValue, "GET")
      if (!ok) throw new Error()
      this.enrolled = !!data.enrolled
      this.enrollStatusTarget.textContent = data.enrolled ? `Enrolled · ${data.sample_count} samples` : "Not enrolled"
    } catch {
      this.enrolled = false
      this.enrollStatusTarget.textContent = "Face ID status unavailable"
    }
    this.removeButtonTarget.hidden = !this.enrolled
    this.enrollButtonTarget.textContent = this.enrolled ? "Re-enroll" : "Enroll face"
  }

  async enroll() {
    if (this.enrollSession) return this.stopEnroll()
    const a = assets()
    if (!a) return this.sayEnroll("Gaze assets missing")
    this.stop()
    this.enrollButtonTarget.disabled = true
    this.sayEnroll("Starting camera and loading models…")
    this.captured = []
    this.lastCapture = 0
    this.camera = { ok: false }
    this.paintSteps()
    try {
      this.lib ??= await import(a.bundle)
      if (this.gone) return
      this.enrollSession = await this.lib.startGazeSession({
        assets: a,
        video: this.enrollPreviewTarget,
        identity: true,
        identityMs: CAPTURE_MS,
        onSample: () => {},
        onHealth: (c) => { this.camera = c },
        onIdentity: (r, now) => this.capture(r, now),
        onError: () => { this.stopEnroll(); this.sayEnroll("Camera unavailable") }
      })
      if (this.gone) return this.stopEnroll()
    } catch {
      this.sayEnroll("Camera unavailable")
    }
    this.enrollButtonTarget.disabled = false
    if (this.enrollSession) {
      this.enrollStageTarget.hidden = false
      this.enrollButtonTarget.textContent = "Cancel"
      this.sayEnroll("Look at the screen, ears visible, no face covering.")
    }
  }

  capture(r, now) {
    if (!this.enrollSession || this.saving) return
    const c = this.lib.enrollChecks({ faces: r.faces, bodies: r.bodies, camera: this.camera })
    const ready = this.lib.allChecks(c)
    this.checkTargets.forEach((el) => { el.dataset.ok = !!c[el.dataset.check] })
    this.enrollStageTarget.dataset.ready = ready
    if (!ready || now - this.lastCapture < CAPTURE_MS) return
    this.lastCapture = now
    this.captured.push(r.faces[0].embedding)
    this.paintSteps()
    this.sayEnroll(`Hold still… ${this.captured.length}/${SAMPLES}`)
    if (this.captured.length >= SAMPLES) this.save()
  }

  async save() {
    this.saving = true
    const descriptors = this.captured.map((d) => Array.from(d))
    this.stopEnroll()
    this.sayEnroll("Saving…")
    const { ok, data } = await call(this.faceUrlValue, "PUT", { descriptors }).catch(() => ({ ok: false, data: {} }))
    this.saving = false
    this.sayEnroll(ok && data.saved ? "Face ID saved. Only you clear the haze." : (data.error || "Could not save face ID. Try again."))
    if (ok && data.saved) window.dispatchEvent(new CustomEvent("privacy-gaze:enrolled"))
    this.loadFace()
  }

  async removeFace() {
    const { ok } = await call(this.faceUrlValue, "DELETE").catch(() => ({ ok: false }))
    this.sayEnroll(ok ? "Face ID removed. The haze stays on until you enroll again." : "Could not remove face ID.")
    if (ok) window.dispatchEvent(new CustomEvent("privacy-gaze:enrolled"))
    this.loadFace()
  }

  stopEnroll() {
    this.enrollSession?.stop()
    this.enrollSession = null
    if (!this.hasEnrollStageTarget) return
    this.enrollStageTarget.hidden = true
    this.enrollStageTarget.dataset.ready = false
    this.checkTargets.forEach((el) => { el.dataset.ok = false })
    this.enrollButtonTarget.disabled = false
    this.enrollButtonTarget.textContent = this.enrolled ? "Re-enroll" : "Enroll face"
  }

  paintSteps() {
    this.enrollStepsTarget.querySelectorAll("i").forEach((el, i) => { el.dataset.on = i < (this.captured?.length || 0) })
  }

  sayEnroll(t) { if (this.hasEnrollMessageTarget) this.enrollMessageTarget.textContent = t }

  // ---- gaze calibration ----

  async toggle() {
    if (this.session) return this.stop()
    const a = assets()
    if (!a) return this.say("Gaze assets missing")
    this.stopEnroll()
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
