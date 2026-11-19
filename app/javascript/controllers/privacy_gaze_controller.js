import { Controller } from "@hotwired/stimulus"

// Looking away from the screen (or losing the camera) fogs the whole app; looking back clears it.
// Fails closed: no camera = haze stays, except on the settings page so it can be switched off.
// The bundle (mediapipe) is lazy and strictly local; see app/javascript/privacy_gaze/.
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }
const RESUME_MS = 3000 // a Turbo visit rebuilds <body>: reuse the last state for that long instead of flashing the haze
let last = { hazy: true, at: 0 }

export default class extends Controller {
  static values = { settingsUrl: String }

  connect() {
    this.gone = false
    this.build()
    this.setHazy(performance.now() - last.at < RESUME_MS ? last.hazy : true, true)
    this.onCalibrated = () => this.baseline && (this.baseline = this.lib.loadBaseline())
    window.addEventListener("privacy-gaze:calibrated", this.onCalibrated)
    this.onVisibility = () => { if (!document.hidden) this.hysteresis?.reset(), this.setHazy(true) }
    document.addEventListener("visibilitychange", this.onVisibility)
    this.start()
  }

  disconnect() {
    this.gone = true
    last = { hazy: this.hazy, at: performance.now() }
    window.removeEventListener("privacy-gaze:calibrated", this.onCalibrated)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.session?.stop()
    this.overlay?.remove()
  }

  async start() {
    this.setError(false)
    const a = assets()
    if (!a) return this.setError(true)
    try {
      this.lib ??= await import(a.bundle)
      if (this.gone) return
      this.baseline = this.lib.loadBaseline()
      this.hysteresis = this.lib.createHysteresis({ initial: this.hazy ? "away" : "looking" })
      this.session?.stop()
      this.session = await this.lib.startGazeSession({
        assets: a,
        onSample: (f, now) => this.setHazy(this.hysteresis.step(this.lib.isLooking(f, this.baseline), now) === "away"),
        onError: () => this.setError(true)
      })
      if (this.gone) this.session.stop()
    } catch {
      this.setError(true)
    }
  }

  retry() { this.start() }

  setHazy(hazy, instant = false) {
    if (hazy === this.hazy && !instant) return
    this.hazy = hazy
    this.overlay.classList.toggle("is-instant", instant)
    this.overlay.dataset.state = hazy ? "hazy" : "clear"
    this.overlay.setAttribute("aria-hidden", hazy ? "false" : "true")
    if (instant) requestAnimationFrame(() => this.overlay.classList.remove("is-instant"))
  }

  setError(on) {
    this.error = on
    if (on) this.setHazy(true)
    this.overlay.classList.toggle("has-error", on)
    // never fog the settings page when the camera is unavailable: the user must be able to turn this off
    const onSettings = this.hasSettingsUrlValue && this.settingsUrlValue &&
      location.pathname === new URL(this.settingsUrlValue, location.href).pathname
    this.overlay.classList.toggle("is-exempt", on && onSettings)
  }

  build() {
    this.overlay = document.createElement("div")
    this.overlay.className = "privacy-haze"
    this.overlay.innerHTML = `
      <div class="privacy-haze__veil"></div>
      <div class="privacy-haze__fog privacy-haze__fog--a"></div>
      <div class="privacy-haze__fog privacy-haze__fog--b"></div>
      <p class="privacy-haze__sr">Privacy haze on</p>
      <div class="privacy-haze__error" role="alert">
        <p>Camera unavailable — privacy haze stays on</p>
        <div><button type="button" class="btn btn-primary btn-sm">Retry</button>
        <a class="btn btn-secondary btn-sm"></a></div>
      </div>`
    const link = this.overlay.querySelector("a")
    link.href = this.settingsUrlValue || "#"
    link.textContent = "Privacy settings"
    this.overlay.querySelector("button").addEventListener("click", () => this.retry())
    document.body.appendChild(this.overlay)
  }
}
