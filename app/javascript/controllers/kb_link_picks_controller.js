import { Controller } from "@hotwired/stimulus"

// Idea form: collect KB links as chips (hidden kb_picks[] = "src:path"); linked on save.
export default class extends Controller {
  static targets = ["chips"]

  add({ detail: r }) {
    this.addPick(r)
  }

  // Draft restore: chips are built client-side, so rebuild them from the saved "src:path" values.
  // ponytail: type is not stored in the draft, restored chips show the file glyph.
  restore(event) {
    if (!event.target.contains(this.element)) return
    ;(event.detail.draft["kb_picks[]"] || []).forEach((value) => {
      const i = value.indexOf(":")
      const path = value.slice(i + 1)
      this.addPick({ src: value.slice(0, i), path, type: "file", name: path.split("/").pop() })
    })
  }

  addPick(r) {
    const value = `${r.src}:${r.path}`
    if ([...this.chipsTarget.querySelectorAll("input")].some((i) => i.value === value)) return
    const chip = document.createElement("span")
    chip.className = "pick-chip"
    const input = Object.assign(document.createElement("input"), { type: "hidden", name: "kb_picks[]", value })
    const label = document.createElement("span")
    label.textContent = `${{ project: "◆", dir: "▸", file: "▫" }[r.type]} ${r.name}`
    const remove = document.createElement("button")
    remove.type = "button"
    remove.textContent = "×"
    remove.setAttribute("aria-label", `Remove ${r.name}`)
    remove.addEventListener("click", () => chip.remove())
    chip.append(input, label, remove)
    this.chipsTarget.append(chip)
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
