import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "search"]
  static values = {
    url: String,
    focusId: { type: String, default: "" },
    showIdeas: { type: Boolean, default: true },
    dagMode: { type: String, default: "" }
  }

  async connect() {
    this._bundleUrl = document.querySelector('meta[name="graph-bundle-url"]')?.content
    this._module = null
    this._graph = null

    // If canvas is already visible (e.g. show page), init immediately.
    // Otherwise wait for it to become visible (hidden tab panel).
    if (this.canvasTarget.offsetParent !== null) {
      await this._initGraph()
    } else {
      this._visibilityObserver = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) {
          this._visibilityObserver.disconnect()
          this._visibilityObserver = null
          this._initGraph()
        }
      })
      this._visibilityObserver.observe(this.canvasTarget)
    }
  }

  async _initGraph() {
    if (this._graph) return

    if (!this._module) {
      this._module = await import(/* webpackIgnore: true */ this._bundleUrl)
    }

    const { TopologyGraph } = this._module

    this._graph = new TopologyGraph(this.canvasTarget, {
      url: this.urlValue,
      focusId: this.focusIdValue,
      showIdeas: this.showIdeasValue,
      dagMode: this.dagModeValue,
    })
  }

  disconnect() {
    if (this._visibilityObserver) this._visibilityObserver.disconnect()
    if (this._graph) this._graph.destroy()
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
