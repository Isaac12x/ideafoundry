import { Controller } from "@hotwired/stimulus"

// The app is fogged unless the ENROLLED person is verified (face match + anti-spoof + liveness + both ears), the camera
// is live (not black/covered/frozen), they are looking at the screen, and nobody else is. Everything fails closed.
// Exception: the settings page stays reachable when there is no face ID / camera, so this can be set up or switched off.
// The bundle (mediapipe + Human) is lazy and strictly local; see app/javascript/privacy_gaze/.
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }
const RESUME_MS = 3000 // a Turbo visit rebuilds <body>: keep the camera session alive this long instead of reloading models
const QUIET = ["away", "stale", "no_face"] // plain haze, no card
const RETRY = ["dark", "frozen", "error"]
const TEXT = { not_enrolled: "Face ID is not set up. The haze stays on until you enroll.", error: "Camera unavailable. Privacy haze stays on." }

// survives controller reconnects (Turbo navigation)
const shared = { session: null, guard: null, lib: null, timer: null, ctl: null, run: 0 }
const teardown = () => { clearTimeout(shared.timer); shared.run++; shared.session?.stop(); shared.session = null; shared.guard = null }

const getFace = async (url) => {
  const r = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
  if (!r.ok) throw new Error(`face ${r.status}`)
  return r.json()
}

export default class extends Controller {
  static values = { settingsUrl: String, faceUrl: String }

  connect() {
    this.build()
    this.onChanged = () => { teardown(); this.hazy = true; this.start() }
    this.onCalibrated = () => shared.guard?.setBaseline(shared.lib.loadBaseline())
    window.addEventListener("privacy-gaze:enrolled", this.onChanged)
    window.addEventListener("privacy-gaze:calibrated", this.onCalibrated)
    this.onVisibility = () => { if (!document.hidden) { shared.guard?.reset(); this.apply(true) } }
    document.addEventListener("visibilitychange", this.onVisibility)
    shared.ctl = this
    if (shared.session || shared.guard) { clearTimeout(shared.timer); this.apply(true) } // resumed after a Turbo visit
    else { this.setHazy(true, true); this.start() }
  }

  disconnect() {
    window.removeEventListener("privacy-gaze:enrolled", this.onChanged)
    window.removeEventListener("privacy-gaze:calibrated", this.onCalibrated)
    document.removeEventListener("visibilitychange", this.onVisibility)
    if (shared.ctl === this) shared.ctl = null
    clearTimeout(shared.timer)
    shared.timer = setTimeout(teardown, RESUME_MS)
    this.overlay?.remove()
  }

  async start() {
    const run = ++shared.run
    const live = () => run === shared.run
    this.reason = null
    const a = assets()
    if (!a || !this.faceUrlValue) return this.show("error")
    try {
      const face = await getFace(this.faceUrlValue)
      const descriptors = face.descriptors || []
      if (!live()) return
      if (!face.enrolled || !descriptors.length) return this.show("not_enrolled")
      shared.lib ??= await import(a.bundle)
      if (!live()) return
      const lib = shared.lib
      const guard = shared.guard = lib.createGuard({ baseline: lib.loadBaseline(), enrolled: true })
      this.messages = lib.MESSAGES
      const session = await lib.startGazeSession({
        assets: a,
        identity: true,
        getDescriptors: () => descriptors,
        onHealth: (c) => { guard.setCamera(c); shared.ctl?.apply() },
        onIdentity: (r, now) => { guard.verify(lib.verifyOwner(r), now); shared.ctl?.apply() },
        onSample: (_f, now, faces) => { guard.gaze(faces, now); shared.ctl?.apply() },
        onError: () => { if (live()) { shared.guard = null; shared.ctl?.show("error") } }
      })
      if (!live()) return session.stop()
      shared.session = session
    } catch {
      if (live()) { shared.guard = null; this.show("error") }
    }
  }

  retry() { teardown(); this.start() }

  apply(instant = false) {
    if (!shared.guard) return
    const d = shared.guard.decision(performance.now())
    this.render(d.hazy, d.reason, instant)
  }

  show(reason) { this.render(true, reason) }

  render(hazy, reason, instant = false) {
    this.reason = reason
    this.setHazy(hazy, instant)
    const card = hazy && !!reason && !QUIET.includes(reason)
    this.overlay.classList.toggle("has-error", card)
    if (card && reason !== this.shownReason) {
      const msg = TEXT[reason] || this.messages?.[reason] || "Privacy haze is on"
      this.overlay.querySelector("[data-msg]").textContent = msg
      this.overlay.querySelector("button").hidden = !RETRY.includes(reason)
      const link = this.overlay.querySelector("a")
      link.textContent = reason === "not_enrolled" ? "Set up face ID" : "Privacy settings"
      link.className = `btn btn-sm ${reason === "not_enrolled" ? "btn-primary" : "btn-secondary"}`
    }
    this.shownReason = card ? reason : null
    // never fog the settings page while there is no face ID / camera: the user must be able to set it up or turn it off
    const onSettings = this.hasSettingsUrlValue && this.settingsUrlValue &&
      location.pathname === new URL(this.settingsUrlValue, location.href).pathname
    this.overlay.classList.toggle("is-exempt", hazy && onSettings && (reason === "not_enrolled" || RETRY.includes(reason)))
  }

  setHazy(hazy, instant = false) {
    if (hazy === this.hazy && !instant) return
    this.hazy = hazy
    this.overlay.classList.toggle("is-instant", instant)
    this.overlay.dataset.state = hazy ? "hazy" : "clear"
    this.overlay.setAttribute("aria-hidden", hazy ? "false" : "true")
    if (instant) requestAnimationFrame(() => this.overlay.classList.remove("is-instant"))
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
        <p data-msg></p>
        <div><button type="button" class="btn btn-primary btn-sm">Retry</button>
        <a class="btn btn-secondary btn-sm"></a></div>
      </div>`
    this.overlay.querySelector("a").href = this.settingsUrlValue || "#"
    this.overlay.querySelector("button").addEventListener("click", () => this.retry())
    document.body.appendChild(this.overlay)
    this.hazy = undefined
  }
}
