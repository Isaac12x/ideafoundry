// Full Unicode emoji picker body shared by every emoji selector (KB folder dialog, display settings).
// Data (app/assets/images/emoji.json, built by scripts/generate_emoji.mjs) is fetched when the host first
// becomes visible, never with the main bundle. Groups use content-visibility so ~4k buttons stay cheap.
let data
const load = (url) => (data ||= fetch(url).then((response) => response.json()))

const words = (text) => text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean)

// Relevance of one emoji for a query, 0 = exclude. Every term must hit a whole word or a word prefix of the name
// (strongest) or keywords; a bare substring only counts inside the name and only for terms of 4+ letters, so "dna"
// finds the DNA emoji and not every keyword that happens to contain those letters.
export function emojiScore(label, keywords, query) {
  const name = words(label)
  const tags = words(keywords || "")
  let total = 0
  for (const term of words(query)) {
    const hit = name.includes(term) ? 100
      : name.some((w) => w.startsWith(term)) ? 60
      : tags.includes(term) ? 40
      : tags.some((w) => w.startsWith(term)) ? 20
      : term.length >= 4 && name.some((w) => w.includes(term)) ? 5
      : 0
    if (!hit) return 0
    total += hit
  }
  return total
}

const SKIN_TONE = /[\u{1F3FB}-\u{1F3FF}]/u
const NEW_CODEPOINT = 0x1fa70 // Unicode 12+ is where older system fonts start drawing tofu

let canvasContext
const supportCache = new Map()

// Whether this platform draws the emoji: a ZWJ sequence it lacks falls apart into several glyphs (wide), a
// codepoint it lacks is drawn monochrome (tofu). Skipped (true) without a canvas, e.g. under node.
export function emojiSupported(emoji, context = canvasContext ||= globalThis.document?.createElement("canvas").getContext("2d", { willReadFrequently: true })) {
  if (!context) return true
  if (supportCache.has(emoji)) return supportCache.get(emoji)
  context.font = "28px sans-serif"
  let ok = true
  if (emoji.includes("\u200d") && context.measureText(emoji).width > context.measureText("\u{1F600}").width * 1.6) ok = false
  else if ([...emoji].some((char) => char.codePointAt(0) >= NEW_CODEPOINT) || emoji.includes("\u200d")) {
    context.clearRect(0, 0, 40, 40)
    context.textBaseline = "top"
    context.fillText(emoji, 0, 0)
    const pixels = context.getImageData(0, 0, 40, 40).data
    ok = false
    for (let i = 0; i < pixels.length && !ok; i += 4) ok = pixels[i + 3] > 128 && Math.max(pixels[i], pixels[i + 1], pixels[i + 2]) - Math.min(pixels[i], pixels[i + 1], pixels[i + 2]) > 40
  }
  supportCache.set(emoji, ok)
  return ok
}

// Base emoji only (skin-tone variants collapse into the base), and only ones this platform can draw.
export const usableEmoji = (list, supported = emojiSupported) => list.filter(([emoji]) => !SKIN_TONE.test(emoji) && supported(emoji))

export function mountEmojiGrid(host, { url, selected, onPick }) {
  const observer = new IntersectionObserver(async (entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return
    observer.disconnect()
    build(host, await load(url), { selected, onPick })
  })
  observer.observe(host)
  return () => observer.disconnect()
}

function build(host, groups, { selected, onPick }) {
  host.replaceChildren()
  const search = Object.assign(document.createElement("input"), { type: "search", className: "kb-emoji-search", placeholder: "Search emoji by name or keyword", autocomplete: "off" })
  search.setAttribute("aria-label", "Search emoji by name or keyword")
  const body = document.createElement("div")
  body.className = "kb-emoji-groups"
  const buttons = []
  for (const [name, list] of groups) {
    const section = document.createElement("section")
    section.className = "kb-emoji-group"
    section.innerHTML = `<h4 class="kb-emoji-group__name"></h4><div class="kb-emoji-grid"></div>`
    section.firstChild.textContent = name
    const grid = section.lastChild
    for (const [emoji, label, keywords = ""] of usableEmoji(list)) {
      const button = Object.assign(document.createElement("button"), { type: "button", className: "kb-emoji-choice", textContent: emoji, title: label })
      button.dataset.emoji = emoji
      button.dataset.label = label
      button.dataset.keywords = keywords
      button.setAttribute("aria-label", label)
      if (emoji === selected) button.classList.add("is-selected")
      buttons.push(button)
      grid.append(button)
    }
    body.append(section)
  }
  const results = Object.assign(document.createElement("div"), { className: "kb-emoji-grid kb-emoji-results", hidden: true })
  host.append(search, results, body)
  body.addEventListener("click", (event) => {
    const button = event.target.closest(".kb-emoji-choice")
    if (!button) return
    event.preventDefault()
    host.querySelectorAll(".kb-emoji-choice").forEach((other) => other.classList.toggle("is-selected", other.dataset.emoji === button.dataset.emoji))
    onPick(button.dataset.emoji, button)
  })
  search.addEventListener("keydown", (event) => { if (event.key === "Enter") event.preventDefault() }) // never submit the form
  // A query swaps the category groups for one grid ranked best match first.
  search.addEventListener("input", () => {
    const query = search.value.trim()
    const ranked = query ? buttons.map((button) => [emojiScore(button.dataset.label, button.dataset.keywords, query), button]).filter(([score]) => score).sort((a, b) => b[0] - a[0]).map(([, button]) => button.cloneNode(true)) : []
    results.replaceChildren(...ranked)
    results.hidden = !query
    body.hidden = !!query
    if (query && !ranked.length) results.append(Object.assign(document.createElement("p"), { className: "kb-emoji-empty", textContent: "No matching emoji" }))
  })
}
