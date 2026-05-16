const VERSION = 1;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function subtleCrypto() {
  return globalThis.crypto?.subtle;
}

function getRandomValues(bytes) {
  return globalThis.crypto.getRandomValues(bytes);
}

function bytesToBase64(bytes) {
  const binary = String.fromCharCode(...new Uint8Array(bytes));
  if (typeof btoa === "function") return btoa(binary);
  return Buffer.from(binary, "binary").toString("base64");
}

function base64ToBytes(value) {
  const binary = typeof atob === "function"
    ? atob(value)
    : Buffer.from(value, "base64").toString("binary");
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function bytesToHex(bytes) {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function canonicalizeDraft(value) {
  if (Array.isArray(value)) return value.map(canonicalizeDraft);
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((acc, key) => {
      acc[key] = canonicalizeDraft(value[key]);
      return acc;
    }, {});
  }
  return value;
}

export async function stableDraftDigest(draft) {
  const subtle = subtleCrypto();
  if (!subtle) throw new Error("Web Crypto is required to protect idea drafts");

  const canonical = JSON.stringify(canonicalizeDraft(draft));
  const digest = await subtle.digest("SHA-256", encoder.encode(canonical));
  return bytesToHex(digest);
}

export function hasMeaningfulDraft(draft) {
  const defaultValues = {
    "idea[state]": "idea_new",
    "idea[trl]": "0",
    "idea[difficulty]": "0",
    "idea[opportunity]": "0",
    "idea[timing]": "0",
  };

  return Object.entries(draft || {}).some(([name, value]) => {
    if (["authenticity_token", "_method", "utf8"].includes(name)) return false;
    if (name.endsWith("[]") && Array.isArray(value)) return value.some((item) => String(item).trim() !== "");

    const normalizedValue = String(value ?? "").trim();
    if (normalizedValue === "") return false;
    if (Object.prototype.hasOwnProperty.call(defaultValues, name) && normalizedValue === defaultValues[name]) return false;

    return true;
  });
}

async function deriveKey({ storageKey, unlockSeed }) {
  const subtle = subtleCrypto();
  if (!subtle) throw new Error("Web Crypto is required to protect idea drafts");

  const material = await subtle.importKey(
    "raw",
    encoder.encode(String(unlockSeed || "")),
    "PBKDF2",
    false,
    ["deriveKey"]
  );

  return subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: encoder.encode(`idea-draft:${storageKey}:${globalThis.location?.origin || "test"}`),
      iterations: 210000,
      hash: "SHA-256",
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
}

export async function encryptDraft(draft, { storageKey, unlockSeed }) {
  if (!hasMeaningfulDraft(draft)) return null;

  const subtle = subtleCrypto();
  if (!subtle) throw new Error("Web Crypto is required to protect idea drafts");

  const iv = getRandomValues(new Uint8Array(12));
  const key = await deriveKey({ storageKey, unlockSeed });
  const plaintext = JSON.stringify(canonicalizeDraft(draft));
  const ciphertext = await subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: encoder.encode(storageKey) },
    key,
    encoder.encode(plaintext)
  );

  return {
    version: VERSION,
    algorithm: "AES-GCM",
    kdf: "PBKDF2-SHA256",
    digest: await stableDraftDigest(draft),
    iv: bytesToBase64(iv),
    ciphertext: bytesToBase64(ciphertext),
    savedAt: new Date().toISOString(),
  };
}

export async function decryptDraft(record, { storageKey, unlockSeed }) {
  const subtle = subtleCrypto();
  if (!subtle) throw new Error("Web Crypto is required to protect idea drafts");
  if (!record || record.version !== VERSION) throw new Error("Unsupported idea draft format");

  const key = await deriveKey({ storageKey, unlockSeed });
  const plaintext = await subtle.decrypt(
    {
      name: "AES-GCM",
      iv: base64ToBytes(record.iv),
      additionalData: encoder.encode(storageKey),
    },
    key,
    base64ToBytes(record.ciphertext)
  );

  return JSON.parse(decoder.decode(plaintext));
}

export function collectDraftFields(form) {
  const draft = {};
  const fields = Array.from(form.elements || []);

  fields.forEach((field) => {
    if (!field.name || field.disabled) return;
    if (["submit", "button", "reset", "file"].includes(field.type)) return;
    if (["authenticity_token", "_method", "utf8"].includes(field.name)) return;

    if (field.type === "checkbox") {
      if (!field.checked) return;
      if (field.name.endsWith("[]")) {
        draft[field.name] ||= [];
        draft[field.name].push(field.value);
      } else {
        draft[field.name] = field.value;
      }
      return;
    }

    if (field.type === "radio") {
      if (field.checked) draft[field.name] = field.value;
      return;
    }

    if (field.name.endsWith("[]")) {
      draft[field.name] ||= [];
      if (field.value !== "") draft[field.name].push(field.value);
      return;
    }

    draft[field.name] = field.value;
  });

  return draft;
}

export function restoreDraftFields(form, draft) {
  Object.entries(draft || {}).forEach(([name, value]) => {
    const fields = Array.from(form.querySelectorAll(`[name="${CSS.escape(name)}"]`));
    fields.forEach((field) => {
      if (field.type === "checkbox") {
        field.checked = Array.isArray(value) ? value.includes(field.value) : String(value) === field.value;
      } else if (field.type === "radio") {
        field.checked = String(value) === field.value;
      } else {
        field.value = Array.isArray(value) ? value[0] || "" : value;
      }
      field.dispatchEvent(new Event("input", { bubbles: true }));
      field.dispatchEvent(new Event("change", { bubbles: true }));
    });
  });

  const description = draft?.["idea[description]"];
  if (description !== undefined) {
    const input = form.querySelector('[name="idea[description]"]');
    input?.dispatchEvent(new CustomEvent("idea-draft:restore-description", {
      bubbles: true,
      detail: { html: description },
    }));
  }
}
