import { decryptDraft, encryptDraft } from "lib/idea_draft_store"

// Unsaved textarea text for KB/project pages. Same protection as the idea drafts: AES-GCM in localStorage with a
// per-user server seed (only present in authenticated pages), so a locked app or a disk copy never exposes the text.
const MAX_CHARS = 400_000
const IGNORED_HIDDEN = ["authenticity_token", "_method", "utf8"]

const body = () => globalThis.document?.body?.dataset || {}

// Page + form + field + the form's hidden ids (src, file, path...), so each logical field has its own draft.
export function draftKey(field) {
  const ids = [...(field.form?.querySelectorAll("input[type=hidden]") || [])]
    .filter((input) => input.name && !IGNORED_HIDDEN.includes(input.name))
    .map((input) => `${input.name}=${input.value}`)
  const where = globalThis.location ? location.pathname + location.search : ""
  return ["fielddraft:v1", body().draftUser, where, field.form?.getAttribute("action") || "", field.name || field.id, ...ids].join("|")
}

const options = (field) => ({ storageKey: draftKey(field), unlockSeed: body().draftSeed })

export async function saveFieldDraft(field) {
  const key = draftKey(field)
  try {
    const record = field.value === field.defaultValue || field.value.length > MAX_CHARS ? null : await encryptDraft({ text: field.value }, options(field))
    record ? localStorage.setItem(key, JSON.stringify(record)) : localStorage.removeItem(key)
  } catch {
    // storage full / no Web Crypto: the page itself still holds the text
  }
}

export function clearFieldDraft(field) {
  try { localStorage.removeItem(draftKey(field)) } catch { /* private mode */ }
}

export function hasFieldDraft(field) {
  try { return localStorage.getItem(draftKey(field)) !== null } catch { return false }
}

// Puts a saved draft back unless the user already typed something new (force: caller just seeded the field).
export async function restoreFieldDraft(field, { force = false } = {}) {
  if (!force && field.value !== field.defaultValue) return false
  try {
    const raw = localStorage.getItem(draftKey(field))
    if (!raw) return false
    const { text } = await decryptDraft(JSON.parse(raw), options(field))
    if (typeof text !== "string" || text === field.value) return false

    field.value = text
    field.dispatchEvent(new Event("input", { bubbles: true }))
    return true
  } catch {
    return false
  }
}
