// Full Unicode emoji picker body shared by every emoji selector (KB folder dialog, display settings).
// Data (app/assets/images/emoji.json, built by scripts/generate_emoji.mjs) is fetched when the host first
// becomes visible, never with the main bundle. Groups use content-visibility so ~4k buttons stay cheap.
let data
const load = (url) => (data ||= fetch(url).then((response) => response.json()))

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
  const search = Object.assign(document.createElement("input"), { type: "search", className: "kb-emoji-search", placeholder: "Search emoji by name", autocomplete: "off" })
  search.setAttribute("aria-label", "Search emoji by name")
  const body = document.createElement("div")
  body.className = "kb-emoji-groups"
  const buttons = []
  for (const [name, list] of groups) {
    const section = document.createElement("section")
    section.className = "kb-emoji-group"
    section.innerHTML = `<h4 class="kb-emoji-group__name"></h4><div class="kb-emoji-grid"></div>`
    section.firstChild.textContent = name
    const grid = section.lastChild
    for (const [emoji, label] of list) {
      const button = Object.assign(document.createElement("button"), { type: "button", className: "kb-emoji-choice", textContent: emoji, title: label })
      button.dataset.emoji = emoji
      button.dataset.name = label.toLowerCase()
      button.setAttribute("aria-label", label)
      if (emoji === selected) button.classList.add("is-selected")
      buttons.push(button)
      grid.append(button)
    }
    body.append(section)
  }
  host.append(search, body)
  body.addEventListener("click", (event) => {
    const button = event.target.closest(".kb-emoji-choice")
    if (!button) return
    event.preventDefault()
    buttons.forEach((other) => other.classList.toggle("is-selected", other === button))
    onPick(button.dataset.emoji, button)
  })
  search.addEventListener("keydown", (event) => { if (event.key === "Enter") event.preventDefault() }) // never submit the form
  search.addEventListener("input", () => {
    const query = search.value.trim().toLowerCase()
    buttons.forEach((button) => { button.hidden = !!query && !button.dataset.name.includes(query) })
    body.querySelectorAll(".kb-emoji-group").forEach((section) => { section.hidden = !section.querySelector(".kb-emoji-choice:not([hidden])") })
  })
}
