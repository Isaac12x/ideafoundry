// Client mirror of Kb::ClipTime (display hint only; the server stays the source of truth).

// First http(s) URL inside a pasted string (wrapped links like chrome-extension://...&uri=https://...).
export function embeddedUrl(text) {
  const t = String(text).trim()
  if (/\s/.test(t)) return null
  const m = t.match(/https?:\/\/\S+/i)
  return m ? m[0] : null
}

export function parseClip(value) {
  const s = String(value ?? "").trim().replace(/^npt:/, "")
  if (!s) return null
  if (s.includes(":")) {
    const parts = s.split(":")
    if (parts.length < 2 || parts.length > 3 || !parts.every((p) => /^\d+(\.\d+)?$/.test(p))) return null
    return Math.floor(parts.reduce((acc, p) => acc * 60 + parseFloat(p), 0))
  }
  const m = s.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s?)?$/i)
  if (!m || !(m[1] || m[2] || m[3])) return null
  return Math.floor(Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 + parseFloat(m[3] || 0))
}

const param = (str, name) => (str.match(new RegExp(`[?&]${name}=([^&#]*)`)) || [])[1]

// => [start, end] seconds or null, like Kb::ClipTime.from_url.
export function clipFromUrl(url) {
  const hash = url.indexOf("#")
  const frag = hash < 0 ? "" : url.slice(hash)
  const query = hash < 0 ? url : url.slice(0, hash)
  const t = frag.match(/[#&]t=([^&]*)/)
  if (t) {
    const [from, to] = t[1].split(",", 2)
    return [parseClip(from), parseClip(to)]
  }
  return [
    parseClip(param(query, "t") ?? param(query, "start") ?? param(frag, "start")),
    parseClip(param(query, "end") ?? param(frag, "end"))
  ]
}

export function formatClip(sec) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
  const pad = (n) => String(n).padStart(2, "0")
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}
