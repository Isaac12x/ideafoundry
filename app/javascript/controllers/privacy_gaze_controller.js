import { Controller } from "@hotwired/stimulus"
import { devtoolsKey, devtoolsOpen, hazeVars, indicatorState, paintIndicator, windowGap } from "lib/privacy_guard"
import { binding } from "lib/shortcut_bindings"

// On protected sections (activeValue) the page CONTENT (<main id="main-content">, never the navigation) is hazed unless
// the ENROLLED person is verified (face match + anti-spoof + liveness + ears), the camera is live, they look at the
// screen, and nobody else does. Hazed = opacity/blur/transform + inert; no text, no overlay. Everything fails closed and
// silently: the reason is only broadcast (privacy-gaze:status) for the settings page.
// Exception: the settings page stays usable with no face ID / camera, so this can be set up or switched off.
// Inactive pages: no camera, no haze (the session is dropped after RESUME_MS).
// The bundle (mediapipe + Human) is lazy and strictly local; see app/javascript/privacy_gaze/.
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }
const RESUME_MS = 3000 // a Turbo visit rebuilds <body>: keep the camera session alive this long instead of reloading models
const DEVTOOLS_POLL_MS = 1000

// survives controller reconnects (Turbo navigation)
const shared = { session: null, guard: null, lib: null, timer: null, ctl: null, run: 0, last: null, gapBase: null, locked: false }
const teardown = () => { clearTimeout(shared.timer); shared.run++; shared.session?.stop(); shared.session = null; shared.guard = null }

const getFace = async (url) => {
  const r = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
  if (!r.ok) throw new Error(`face ${r.status}`)
  return r.json()
}

export default class extends Controller {
  static values = {
    settingsUrl: String, faceUrl: String, lockUrl: String,
    active: { type: Boolean, default: false },
    awayMs: { type: Number, default: 2500 }, clearMs: { type: Number, default: 150 }, sensitivity: { type: Number, default: 5 }, strength: { type: Number, default: 6 },
  }

  connect() {
    this.hazy = undefined
    this.devtools = false
    this.onChanged = () => { teardown(); this.start() }
    this.onCalibrated = () => shared.guard?.setCalibration(shared.lib.loadEnvelope())
    this.onVisibility = () => { if (!document.hidden) { shared.guard?.reset(); this.apply(true) } }
    // capture: a page script must not swallow these. Only while hazed on a protected page.
    this.onKey = (e) => { if (this.locking() && devtoolsKey(e)) { e.preventDefault(); e.stopPropagation() } }
    this.onMenu = (e) => { if (this.locking()) { e.preventDefault(); e.stopPropagation() } }
    this.onResize = () => this.checkDevtools()
    window.addEventListener("privacy-gaze:enrolled", this.onChanged)
    window.addEventListener("privacy-gaze:calibrated", this.onCalibrated)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("keydown", this.onKey, true)
    window.addEventListener("contextmenu", this.onMenu, true)
    window.addEventListener("resize", this.onResize)
    shared.ctl = this
    this.applyStrength()
    this.paint(false)

    if (!this.activeValue) { // inactive page: nothing hazed; a running session ends after RESUME_MS (timer set on disconnect)
      this.setHazy(false, true)
      return
    }
    this.poll = setInterval(() => this.checkDevtools(), DEVTOOLS_POLL_MS)
    if (shared.session || shared.guard) {
      clearTimeout(shared.timer)
      shared.guard?.setTuning(this.tuning()) // resumed after a Turbo visit
      this.apply(true)
    } else { this.setHazy(true, true); this.start() }
  }

  disconnect() {
    window.removeEventListener("privacy-gaze:enrolled", this.onChanged)
    window.removeEventListener("privacy-gaze:calibrated", this.onCalibrated)
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("keydown", this.onKey, true)
    window.removeEventListener("contextmenu", this.onMenu, true)
    window.removeEventListener("resize", this.onResize)
    clearInterval(this.poll)
    if (shared.ctl === this) shared.ctl = null
    clearTimeout(shared.timer)
    shared.timer = setTimeout(teardown, RESUME_MS)
  }

  strengthValueChanged() { this.applyStrength() }

  applyStrength() { for (const [k, v] of Object.entries(hazeVars(this.strengthValue))) this.element.style.setProperty(k, v) }

  // nav eye: this controller only exists while the feature is on
  paint(hazy) { paintIndicator(document.querySelector("[data-privacy-indicator]"), indicatorState(true, hazy), binding("privacy_haze")) }

  tuning() { return { sensitivity: this.sensitivityValue, awayMs: this.awayMsValue, clearMs: this.clearMsValue } }

  locking() { return this.activeValue && this.hazy }

  // Docked devtools shrink the inner window. ponytail: undocked devtools slip past this; the keys/menu block and the
  // lock are best effort, browser menus can still open devtools.
  checkDevtools() {
    if (!this.activeValue) return
    const gap = windowGap(window)
    const open = shared.gapBase ? devtoolsOpen(gap, shared.gapBase) : false
    // baseline = the gap while clear and not open (sidebars/side panels move it freely; devtools jump it by > 160px)
    if (!open && this.hazy === false) shared.gapBase = gap
    if (open === this.devtools) return
    this.devtools = open
    if (open) { this.setHazy(true, true); this.lockWorkspace() } else this.apply()
  }

  // Same approach as typing_activity_controller: cover at once, then a form POST to the lock action. At most once per page load.
  lockWorkspace() {
    if (!this.lockUrlValue || shared.locked) return
    shared.locked = true
    const cover = document.createElement("div")
    cover.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#0b0b0f"
    document.documentElement.appendChild(cover)
    if (document.body) document.body.inert = true
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.lockUrlValue
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) {
      const input = Object.assign(document.createElement("input"), { type: "hidden", name: "authenticity_token", value: token })
      form.appendChild(input)
    }
    document.documentElement.appendChild(form)
    form.submit()
  }

  async start() {
    if (!this.activeValue) return
    const run = ++shared.run
    const live = () => run === shared.run
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
      const guard = shared.guard = lib.createGuard({ envelope: lib.loadEnvelope(), enrolled: true, ...this.tuning() })
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

  apply(instant = false) {
    if (!this.activeValue || !shared.guard) return
    const d = shared.guard.decision(performance.now())
    this.render(d.hazy || this.devtools, d.reason, instant)
  }

  show(reason) { this.render(true, reason) }

  render(hazy, reason, instant = false) {
    // never haze the settings page while there is no face ID / camera: the user must be able to set it up or turn it off
    const onSettings = this.settingsUrlValue && location.pathname === new URL(this.settingsUrlValue, location.href).pathname
    if (hazy && onSettings && !this.devtools && (reason === "not_enrolled" || reason === "error")) hazy = false
    this.setHazy(hazy, instant)
    const text = hazy ? (this.messages?.[reason] || (reason === "error" ? "Camera unavailable" : reason === "not_enrolled" ? "Face ID is not set up" : "Privacy haze is on")) : "Clear"
    const key = `${hazy}:${reason}`
    if (shared.last !== key) {
      shared.last = key
      window.dispatchEvent(new CustomEvent("privacy-gaze:status", { detail: { hazy, reason, text } }))
    }
  }

  // The page content only (never the navigation). Class drives opacity/blur/transform; inert blocks focus + AT.
  setHazy(hazy, instant = false) {
    const main = document.getElementById("main-content")
    document.body.dataset.privacyGazeState = hazy ? "hazy" : "clear"
    this.paint(hazy)
    if (hazy === this.hazy && !instant) return
    this.hazy = hazy
    if (!main) return
    main.classList.toggle("is-instant", instant)
    main.classList.toggle("privacy-hazed", hazy)
    main.inert = hazy
    if (hazy) { document.activeElement?.blur?.(); getSelection()?.removeAllRanges() }
    if (instant) requestAnimationFrame(() => main.classList.remove("is-instant"))
  }
}
