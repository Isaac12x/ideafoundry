import { Controller } from "@hotwired/stimulus"

// Renders a ```mermaid fence (and flowchart/sequenceDiagram/... aliases) as an
// SVG. Mermaid lives in its own bundle, imported on first use only.
// securityLevel "strict": labels are sanitised and click handlers disabled.
let loading = null
let queue = Promise.resolve()
let seq = 0
const KEYWORD = /^(graph|flowchart|stateDiagram|classDiagram|sequenceDiagram|erDiagram|gantt|pie|journey|mindmap|timeline)\b/i

function loadMermaid(url) {
  if (window.IdeaApp?.mermaid) return Promise.resolve(window.IdeaApp.mermaid)
  loading ||= import(/* webpackIgnore: true */ url).then(() => window.IdeaApp.mermaid)
    .catch((error) => { loading = null; throw error })
  return loading
}

// Follow the app theme: dark when the page background is dark.
function appTheme() {
  const m = getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g)
  if (!m) return "dark"
  const [r, g, b] = m.map(Number)
  return (0.299 * r + 0.587 * g + 0.114 * b) < 128 ? "dark" : "default"
}

// Mermaid needs concrete colours, so resolve the app's tokens (edge-label boxes otherwise stay grey).
function themeVariables() {
  const css = getComputedStyle(document.body)
  const token = (name) => css.getPropertyValue(name).trim() || undefined
  return { edgeLabelBackground: token("--bg-surface") || css.backgroundColor, fontFamily: css.fontFamily }
}

export default class extends Controller {
  static values = { url: String, keyword: String }

  async connect() {
    // Turbo snapshots before disconnect(), so a restored page still carries the last render.
    this.element.querySelectorAll(":scope > .kb-diagram-out, :scope > .kb-diagram-bar, :scope > .kb-diagram-error").forEach((el) => el.remove())
    this.source = (this.element.querySelector("code")?.textContent || "").trim()
    this.pre = this.element.querySelector(":scope > pre")
    const out = this.out = document.createElement("div")
    out.className = "kb-diagram-out"
    out.setAttribute("role", "img")
    out.setAttribute("aria-label", "Diagram")
    this.element.prepend(out)
    this.pre.hidden = true
    this.addToolbar()

    try {
      const mermaid = await loadMermaid(this.urlValue)
      const svg = await this.enqueue(mermaid)
      if (!out.isConnected) return
      out.innerHTML = svg
      const title = out.querySelector("svg > title")?.textContent.trim()
      if (title) out.setAttribute("aria-label", title)
    } catch (error) {
      if (out.isConnected) this.fail(error, out)
    }
  }

  disconnect() {
    this.out?.remove()
    this.bar?.remove()
    this.error?.remove()
    if (this.pre) this.pre.hidden = false
  }

  // mermaid.render shares global state; serialise renders.
  enqueue(mermaid) {
    const run = async () => {
      // suppressErrorRendering: on a parse error mermaid otherwise leaves its "Syntax error" bomb SVG in <body>.
      mermaid.initialize({ startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true, theme: appTheme(), themeVariables: themeVariables() })
      const { svg } = await mermaid.render(`kb-diagram-${++seq}`, this.mermaidSource())
      return svg
    }
    const result = queue.then(run)
    queue = result.catch(() => {})
    return result
  }

  // Alias fences may omit the diagram keyword (```flowchart / A --> B).
  mermaidSource() {
    const kw = this.keywordValue
    if (!kw || KEYWORD.test(this.source)) return this.source
    const dir = /^(TB|TD|BT|RL|LR)\b/.test(this.source)
    return kw === "flowchart" && !dir ? `${kw} TD\n${this.source}` : `${kw}${dir ? " " : "\n"}${this.source}`
  }

  fail(error, out) {
    out.remove()
    this.error = document.createElement("div")
    this.error.className = "kb-diagram-error"
    this.error.setAttribute("role", "alert")
    const msg = document.createElement("strong")
    msg.textContent = "Diagram could not be rendered"
    const detail = document.createElement("pre")
    detail.textContent = String(error?.message || error)
    this.error.append(msg, detail)
    this.element.prepend(this.error)
    this.pre.hidden = false
    this.toggle.hidden = true
  }

  addToolbar() {
    this.bar = document.createElement("div")
    this.bar.className = "kb-diagram-bar"
    this.bar.setAttribute("aria-live", "polite")
    this.toggle = this.button("Source", () => {
      this.pre.hidden = !this.pre.hidden
      this.toggle.setAttribute("aria-pressed", String(!this.pre.hidden))
    })
    this.toggle.setAttribute("aria-pressed", "false")
    const copy = this.button("Copy", async () => {
      try {
        await navigator.clipboard.writeText(this.source)
        copy.textContent = "Copied"
      } catch { copy.textContent = "Copy failed" }
      setTimeout(() => { copy.textContent = "Copy" }, 1500)
    })
    this.bar.append(this.toggle, copy)
    this.element.append(this.bar)
  }

  button(label, onClick) {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "kb-diagram-btn"
    b.textContent = label
    b.addEventListener("click", onClick)
    return b
  }
}
