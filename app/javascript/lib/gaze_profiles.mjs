// Per-screen gaze calibration profiles (pure, no DOM): the camera/screen geometry differs per monitor, so each screen
// gets its own envelope. Stored in localStorage (this device only), as before, but as a list of profiles.
export const FEATURES = ["yaw", "pitch", "h", "v"]
export const STORE_KEY = "privacy-gaze:envelope" // legacy: one envelope, migrated into the first profile
export const PROFILES_KEY = "privacy-gaze:profiles"
export const DEFAULT_ENVELOPE = {
  center: { yaw: 0, pitch: 0, h: 0, v: 0 },
  min: { yaw: -15, pitch: -12, h: -0.25, v: -0.3 },
  max: { yaw: 15, pitch: 12, h: 0.25, v: 0.3 },
}

// Stable id of the screen the window is on: size + position in the virtual desktop (a monitor above the laptop has a
// different availTop than one beside it). ponytail: devicePixelRatio is NOT in the key (browser zoom changes it);
// the screen label (getScreenDetails) is only a display name. Two screens of equal size at equal offset can't coexist.
export function screenKey(scr = globalThis.screen) {
  if (!scr?.width || !scr?.height) return "unknown"
  return `${scr.width}x${scr.height}@${scr.availLeft ?? scr.left ?? 0},${scr.availTop ?? scr.top ?? 0}`
}

export function defaultScreenName(scr = globalThis.screen, label) {
  if (label) return label
  return scr?.width ? `${scr.width}×${scr.height} screen${scr.isInternal ? " (built-in)" : ""}` : "This screen"
}

export const validEnvelope = (e) => !!e && ["center", "min", "max"].every((p) => FEATURES.every((k) => Number.isFinite(e[p]?.[k])))

const read = (storage, key) => { try { return JSON.parse(storage.getItem(key)) } catch { return null } }

// -> [{ key, name, envelope, updatedAt }]. A legacy single envelope becomes the first profile (of the current screen).
export function loadProfiles(storage = globalThis.localStorage, scr = globalThis.screen) {
  const stored = read(storage, PROFILES_KEY)
  if (Array.isArray(stored?.profiles)) return stored.profiles.filter((p) => p?.key && validEnvelope(p.envelope))
  const legacy = read(storage, STORE_KEY)
  if (!validEnvelope(legacy)) return []
  const profiles = [{ key: screenKey(scr), name: defaultScreenName(scr), envelope: legacy, updatedAt: Date.now() }]
  saveProfiles(profiles, storage)
  try { storage.removeItem(STORE_KEY) } catch {}
  return profiles
}

export function saveProfiles(profiles, storage = globalThis.localStorage) {
  try { storage.setItem(PROFILES_KEY, JSON.stringify({ v: 1, profiles })); return true } catch { return false }
}

// profile for this screen key, or undefined (= uncalibrated screen)
export const profileFor = (profiles, key) => profiles.find((p) => p.key === key)

export function loadEnvelope(storage = globalThis.localStorage, scr = globalThis.screen) {
  return profileFor(loadProfiles(storage, scr), screenKey(scr))?.envelope || DEFAULT_ENVELOPE
}
export function hasEnvelope(storage = globalThis.localStorage, scr = globalThis.screen) {
  return !!profileFor(loadProfiles(storage, scr), screenKey(scr))
}

// add or replace (recalibrate) the profile of this screen; a kept name survives recalibration
export function saveEnvelope(envelope, storage = globalThis.localStorage, scr = globalThis.screen, name) {
  const key = screenKey(scr)
  const profiles = loadProfiles(storage, scr)
  const old = profileFor(profiles, key)
  const next = { key, name: name || old?.name || defaultScreenName(scr), envelope, updatedAt: Date.now() }
  return saveProfiles(old ? profiles.map((p) => (p.key === key ? next : p)) : [...profiles, next], storage)
}

export function renameProfile(key, name, storage = globalThis.localStorage) {
  const n = String(name || "").trim().slice(0, 60)
  if (!n) return false
  return saveProfiles(loadProfiles(storage).map((p) => (p.key === key ? { ...p, name: n } : p)), storage)
}

export function deleteProfile(key, storage = globalThis.localStorage) {
  return saveProfiles(loadProfiles(storage).filter((p) => p.key !== key), storage)
}
