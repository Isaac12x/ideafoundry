import { Controller } from "@hotwired/stimulus"
import { defaultScreenName, deleteProfile, loadProfiles, profileFor, renameProfile, saveEnvelope, screenKey } from "lib/gaze_profiles"

// Settings panel: guided 5-point calibration (a dot at the centre, then the four corners of the viewport, ~1.5s each)
// stores this device's "screen envelope" (the camera sits above the screen, so "looking" is never yaw/pitch 0), one
// profile per screen (laptop, external monitor above or beside it): listed here to rename / recalibrate / delete.
// Afterwards the camera stays on as a live Looking/Away test next to the preview. Also shows the live haze status.
const SETTLE_MS = 700 // dot travel + eyes catching up
const COLLECT_MS = 800
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const assets = () => { try { return JSON.parse(document.querySelector('meta[name="privacy-gaze-assets"]')?.content) } catch { return null } }

const SAMPLES = 5 // face descriptors stored per enrollment
const CAPTURE_MS = 400
const verified = () => document.body.dataset.privacyGazeVerified === "true" // see privacy_gaze_controller render()
const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content
const call = (url, method, body) => fetch(url, {
  method, credentials: "same-origin",
  headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf() },
  body: body && JSON.stringify(body),
}).then(async (r) => ({ ok: r.ok, data: await r.json().catch(() => ({})) }))

export default class extends Controller {
  static targets = ["button", "status", "preview", "live", "message",
    "stage", "haze", "profiles", "enrollButton", "enrollStatus", "enrollStage", "enrollPreview", "enrollMessage", "enrollSteps", "check", "removeButton"]
  static values = { faceUrl: String }

  connect() {
    this.gone = false
    this.showStatus()
    this.shownKey = screenKey()
    this.screenPoll = setInterval(() => { if (screenKey() !== this.shownKey) { this.shownKey = screenKey(); this.showStatus() } }, 1000)
    this.loadFace()
    this.onStatus = (e) => this.paintHaze(e.detail)
    window.addEventListener("privacy-gaze:status", this.onStatus)
  }
  disconnect() { this.gone = true; clearInterval(this.screenPoll); window.removeEventListener("privacy-gaze:status", this.onStatus); this.stop(); this.stopEnroll() }

  // body[data-privacy-gaze-setup] hides the floating notes / shortcuts / agent widgets (privacy_gaze.css) while a camera setup runs
  syncSetup() { document.body.toggleAttribute("data-privacy-gaze-setup", !!(this.stageEl || this.enrollSession)) }

  paintHaze({ hazy, text }) {
    // the live haze guard watches the same camera: while enrolling/calibrating the user is deliberately off-centre or
    // looking elsewhere, so its verdict ("someone else", "away") is not shown over the setup
    if (!this.hasHazeTarget || this.stageEl || this.enrollSession) return
    this.hazeTarget.hidden = false
    this.hazeTarget.dataset.hazy = hazy
    this.hazeTarget.textContent = hazy ? `Hazed: ${text}` : "Haze: clear"
  }

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
    this.syncSetup()
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
    const { ok, data } = await call(this.faceUrlValue, "PUT", { descriptors, clear: verified() }).catch(() => ({ ok: false, data: {} }))
    this.saving = false
    this.sayEnroll(ok && data.saved ? "Face ID saved. Only you clear the haze." : (data.error || "Could not save face ID. Try again."))
    if (ok && data.saved) window.dispatchEvent(new CustomEvent("privacy-gaze:enrolled"))
    this.loadFace()
  }

  async removeFace() {
    const { ok, data } = await call(this.faceUrlValue, "DELETE", { clear: verified() }).catch(() => ({ ok: false }))
    this.sayEnroll(ok ? "Face ID removed. The haze stays on until you enroll again." : (data?.error || "Could not remove face ID."))
    if (ok) window.dispatchEvent(new CustomEvent("privacy-gaze:enrolled"))
    this.loadFace()
  }

  stopEnroll() {
    this.enrollSession?.stop()
    this.enrollSession = null
    this.syncSetup()
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
      this.envelope = this.lib.loadEnvelope() // this screen's profile
      this.collecting = null
      this.session = await this.lib.startGazeSession({
        assets: a,
        video: this.previewTarget,
        onSample: (f) => this.sample(f),
        onError: () => { this.stop(); this.say("Camera unavailable") }
      })
      if (this.gone) return this.stop()
    } catch {
      this.say("Camera unavailable")
    }
    this.syncSetup()
    this.buttonTarget.disabled = false
    if (!this.session) return
    this.buttonTarget.textContent = "Stop"
    this.calibrate()
  }

  // Dot at the centre, then each corner. Samples are collected per point only after the settle time.
  async calibrate() {
    const lib = this.lib
    const run = this.run = (this.run || 0) + 1
    const live = () => this.run === run && this.session && !this.gone
    const stage = this.buildStage(() => this.stop())
    const perPoint = lib.CALIBRATION_POINTS.map(() => [])
    await sleep(500) // camera warm-up
    for (let i = 0; i < lib.CALIBRATION_POINTS.length && live(); i++) {
      const p = lib.CALIBRATION_POINTS[i]
      stage.go(p, i + 1, lib.CALIBRATION_POINTS.length)
      await sleep(SETTLE_MS)
      if (!live()) break
      this.collecting = perPoint[i]
      await sleep(COLLECT_MS)
      this.collecting = null
    }
    stage.remove()
    if (!live()) return
    const env = lib.buildEnvelope(perPoint)
    const known = profileFor(loadProfiles(), screenKey())
    if (env && saveEnvelope(env, undefined, undefined, known ? undefined : defaultScreenName(screen, await this.screenLabel()))) {
      this.envelope = env
      this.shownKey = screenKey()
      window.dispatchEvent(new CustomEvent("privacy-gaze:calibrated"))
      this.say("Calibrated. Look around the screen, then away, to test.")
    } else {
      this.say("Could not see your face at every point. Try again in better light.")
    }
    this.showStatus()
    this.stageTarget.hidden = false
    this.previewTarget.hidden = false
  }

  buildStage(onCancel) {
    const el = document.createElement("div")
    el.className = "privacy-stage"
    el.setAttribute("role", "dialog")
    el.setAttribute("aria-label", "Calibration")
    el.innerHTML = `<span class="privacy-stage__count"></span><span class="privacy-stage__dot"></span>
      <p class="privacy-stage__hint">Keep your head still and follow the dot with your eyes.</p>
      <button type="button" class="btn btn-secondary btn-sm privacy-stage__cancel">Cancel</button>`
    const dot = el.querySelector(".privacy-stage__dot"), count = el.querySelector(".privacy-stage__count")
    dot.style.left = "50%"; dot.style.top = "50%"
    el.querySelector("button").addEventListener("click", onCancel)
    document.body.appendChild(el)
    el.querySelector("button").focus()
    this.stageEl = el
    this.syncSetup()
    return {
      go: (p, n, total) => { dot.style.left = `${p.x * 100}%`; dot.style.top = `${p.y * 100}%`; count.textContent = `${n} / ${total}` },
      remove: () => { el.remove(); if (this.stageEl === el) this.stageEl = null; this.syncSetup() },
    }
  }

  sample(f) {
    if (this.collecting && f) this.collecting.push(f)
    if (this.stageEl) return
    const looking = this.lib.isLooking(f, this.envelope, this.currentSensitivity())
    this.liveTarget.textContent = looking ? "Looking" : "Away"
    this.liveTarget.dataset.looking = looking
  }

  currentSensitivity() {
    return Number(document.getElementById("privacy_gaze_sensitivity")?.value) || 5
  }

  stop() {
    this.run = (this.run || 0) + 1
    this.collecting = null
    this.stageEl?.remove()
    this.stageEl = null
    this.syncSetup()
    this.session?.stop()
    this.session = null
    this.syncSetup()
    if (this.hasPreviewTarget) this.previewTarget.hidden = true
    if (this.hasStageTarget) this.stageTarget.hidden = true
    if (this.hasButtonTarget) { this.buttonTarget.disabled = false; this.showStatus() }
    if (this.hasLiveTarget) this.liveTarget.textContent = ""
  }

  // Display name of the current screen. Needs the window-management permission (Chrome); anything else -> null.
  async screenLabel() {
    try {
      if (!window.getScreenDetails) return null
      const state = (await navigator.permissions.query({ name: "window-management" })).state
      if (state === "denied") return null
      return (await window.getScreenDetails()).currentScreen?.label || null
    } catch { return null }
  }

  showStatus() {
    const key = screenKey()
    const profiles = loadProfiles()
    const here = profileFor(profiles, key)
    if (this.hasStatusTarget) this.statusTarget.textContent = here ? `Calibrated · ${here.name}` : "This screen is not calibrated"
    if (this.hasButtonTarget && !this.session) this.buttonTarget.textContent = here ? "Recalibrate" : "Calibrate"
    if (!this.hasProfilesTarget) return
    this.profilesTarget.hidden = !profiles.length
    this.profilesTarget.replaceChildren(...profiles.map((p) => this.profileRow(p, p.key === key)))
  }

  profileRow(p, current) {
    const li = document.createElement("li")
    li.className = "privacy-profile"
    const name = Object.assign(document.createElement("input"), { type: "text", value: p.name, maxLength: 60 })
    name.className = "privacy-profile__name"
    name.setAttribute("aria-label", `Name of screen ${p.name}`)
    name.addEventListener("change", () => { if (!renameProfile(p.key, name.value)) name.value = p.name; this.showStatus() })
    const tag = Object.assign(document.createElement("span"), { className: "privacy-profile__tag", textContent: current ? "This screen" : "" })
    const recal = Object.assign(document.createElement("button"), { type: "button", className: "btn btn-secondary btn-sm", textContent: "Recalibrate", disabled: !current })
    recal.title = current ? "" : "Move this window to that screen to recalibrate it"
    recal.addEventListener("click", () => this.toggle())
    const del = Object.assign(document.createElement("button"), { type: "button", className: "btn btn-secondary btn-sm", textContent: "Delete" })
    del.setAttribute("aria-label", `Delete calibration of ${p.name}`)
    del.addEventListener("click", () => {
      deleteProfile(p.key)
      window.dispatchEvent(new CustomEvent("privacy-gaze:calibrated"))
      this.showStatus()
    })
    li.append(name, tag, recal, del)
    return li
  }

  say(t) { if (this.hasMessageTarget) this.messageTarget.textContent = t }
}
