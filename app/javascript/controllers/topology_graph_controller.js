import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "search"]
  static values = {
    url: String,
    bundleUrl: String,
    focusId: { type: String, default: "" },
    showIdeas: { type: Boolean, default: true },
    dagMode: { type: String, default: "" }
  }

  async connect() {
    this._disconnected = false
    this._module = null
    this._graph = null
    this._boundTabShown = () => this._maybeInitGraph()

    // If canvas is already visible (e.g. show page), init immediately.
    // Otherwise wait for the graph tab or intersection (hidden tab panel).
    this.element.addEventListener("tab:shown", this._boundTabShown)
    if (this.canvasTarget.offsetParent !== null) {
      await this._maybeInitGraph()
    } else {
      this._visibilityObserver = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) {
          this._visibilityObserver.disconnect()
          this._visibilityObserver = null
          this._maybeInitGraph()
        }
      })
      this._visibilityObserver.observe(this.canvasTarget)
    }
  }

  async _maybeInitGraph() {
    if (this.canvasTarget.offsetParent === null) return
    await this._initGraph()
  }

  async _initGraph() {
    if (this._graph) return

    const bundleUrl = this.bundleUrlValue
    if (!bundleUrl) return

    if (!this._module) {
      this._module = await import(/* webpackIgnore: true */ bundleUrl)
    }

    if (this._disconnected) return // controller left DOM while the bundle loaded
    if (this._graph) return
    const { TopologyGraph } = this._module

    this._graph = new TopologyGraph(this.canvasTarget, {
      url: this.urlValue,
      focusId: this.focusIdValue,
      showIdeas: this.showIdeasValue,
      dagMode: this.dagModeValue,
    })
  }

  disconnect() {
    this._disconnected = true
    if (this._boundTabShown) this.element.removeEventListener("tab:shown", this._boundTabShown)
    if (this._visibilityObserver) this._visibilityObserver.disconnect()
    if (this._graph) this._graph.destroy()
    this._graph = null
  }

  toggleIdeas() {
    if (!this._graph) return
    this._graph.toggleIdeas()
    this.showIdeasValue = this._graph.showIdeas
  }

  toggleDag() {
    if (!this._graph) return
    this.dagModeValue = this._graph.toggleDag()
  }

  zoomIn()  { this._graph?.zoomIn() }
  zoomOut() { this._graph?.zoomOut() }
  fitAll()  { this._graph?.fitAll() }

  search(event) {
    this._graph?.search(event?.target?.value || "")
  }
}
