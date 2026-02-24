import ForceGraph3D from '3d-force-graph'
import { setupScene, addBloom } from './scene.js'
import { makeNodeObject } from './nodes.js'
import { applyHighlights } from './highlights.js'
import { startAnimationLoop } from './animation.js'
import { debouncedRebuildClusters } from './clusters.js'
import { subscribe, applyPatch } from './cable.js'
import { buildConnectedMap, filteredData, escapeHtml } from './helpers.js'

export class TopologyGraph {
  constructor(el, opts = {}) {
    this._el = el
    this._data = null
    this._settings = {}
    this._graph = null
    this._nodeMap = new Map()
    this._connectedMap = new Map()
    this._hoveredNode = null
    this._searchTerm = ""
    this._stopAnimation = null
    this._resizeObserver = null
    this._pointLight = null
    this._subscription = null

    this._showIdeas = opts.showIdeas !== false
    this._focusId = opts.focusId || ""
    this._dagMode = opts.dagMode || ""
    this._url = opts.url

    this._onHighlightsChanged = opts.onHighlightsChanged || null

    this._init()
  }

  async _init() {
    try {
      const res = await fetch(this._url)
      if (!res.ok) throw new Error(`Graph data fetch failed: ${res.status}`)
      this._data = await res.json()
    } catch (e) {
      console.error("TopologyGraph: failed to load graph data", e)
      return
    }
    this._settings = this._data.settings || {}

    if (this._settings.show_ideas !== undefined) this._showIdeas = this._settings.show_ideas
    if (this._settings.default_dag_mode !== undefined) this._dagMode = this._settings.default_dag_mode

    this._connectedMap = buildConnectedMap(this._data)
    this._buildGraph()
    this._subscribeCable()
  }

  _buildGraph() {
    const el = this._el
    const data = this._showIdeas ? this._data : filteredData(this._data)

    this._graph = ForceGraph3D()(el)
      .backgroundColor('#0c0c0f')
      .graphData(data)
      .warmupTicks(80)
      .cooldownTicks(60)
      .nodeVal(n => n.val || (n.type === 'idea' ? (this._settings.node_size_idea || 3) : (this._settings.node_size_topology || 6)))
      .nodeThreeObject(n => makeNodeObject(n, this._nodeMap, this._settings))
      .nodeThreeObjectExtend(false)
      .nodeLabel(n => n.type === 'idea' ? `<div class="graph-tooltip">${escapeHtml(n.name || '')}</div>` : '')
      // Links
      .linkColor(l => l.type === 'parent' ? 'rgba(232,176,74,0.6)' : 'rgba(212,149,58,0.12)')
      .linkWidth(l => l.type === 'parent' ? 1.8 : 0.3)
      .linkCurvature(l => l.type === 'parent' ? 0.15 : 0)
      .linkDirectionalParticles(l => l.type === 'parent' ? 3 : 0)
      .linkDirectionalParticleSpeed(0.008)
      .linkDirectionalParticleWidth(2.0)
      .linkDirectionalParticleColor(() => '#e8b04a')
      .linkOpacity(0.6)
      .onNodeHover(node => this._onHover(node))
      .onNodeClick(node => this._onClick(node))
      .width(el.clientWidth)
      .height(el.clientHeight)

    if (this._dagMode) this._graph.dagMode(this._dagMode)

    // Scene atmosphere + bloom
    this._pointLight = setupScene(this._graph, this._settings)
    addBloom(this._graph, this._settings)

    // Focus / auto-fit on first engine stop, then persistent cluster rebuilds
    let initialStop = true
    this._graph.onEngineStop(() => {
      if (initialStop) {
        initialStop = false
        if (this._focusId) {
          const focusNode = this._graph.graphData().nodes.find(n => n.id === this._focusId)
          if (focusNode && focusNode.x !== undefined) {
            const distance = 120
            const distRatio = 1 + distance / Math.hypot(focusNode.x, focusNode.y, focusNode.z)
            this._graph.cameraPosition(
              { x: focusNode.x * distRatio, y: focusNode.y * distRatio, z: focusNode.z * distRatio },
              focusNode, 1500
            )
          }
        } else if (this._settings.auto_fit_on_load !== false) {
          this._graph.zoomToFit(600, 40)
        }
      }
      // Always rebuild cluster hulls when engine settles
      debouncedRebuildClusters(this._graph)
    })

    // Animation loop
    this._stopAnimation = startAnimationLoop(
      this._graph, this._pointLight, this._nodeMap,
      () => ({ hoveredNode: this._hoveredNode, searchTerm: this._searchTerm })
    )

    // Resize observer
    this._resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        this._graph.width(entry.contentRect.width).height(entry.contentRect.height)
      }
    })
    this._resizeObserver.observe(el)
  }

  _onClick(node) {
    const behavior = this._settings.click_behavior || 'navigate'
    if (behavior === 'focus') {
      if (!node) return
      const distance = 120
      const distRatio = 1 + distance / Math.hypot(node.x, node.y, node.z)
      this._graph.cameraPosition(
        { x: node.x * distRatio, y: node.y * distRatio, z: node.z * distRatio },
        node, 1000
      )
    } else {
      if (node.url && window.Turbo) {
        window.Turbo.visit(node.url)
      } else if (node.url) {
        window.location.href = node.url
      }
    }
  }

  _onHover(node) {
    this._hoveredNode = node || null
    this._applyHighlights()
    this._el.style.cursor = node ? 'pointer' : 'default'
  }

  _applyHighlights() {
    if (!this._graph) return
    applyHighlights(this._graph, this._nodeMap, this._connectedMap, this._hoveredNode, this._searchTerm)
  }

  _subscribeCable() {
    this._subscription = subscribe((patch) => {
      const changed = applyPatch(this._data, patch, (d) => {
        this._connectedMap = buildConnectedMap(d)
        return true
      })
      if (changed) {
        this._nodeMap.clear()
        const data = this._showIdeas ? this._data : filteredData(this._data)
        this._graph.graphData(data)
        debouncedRebuildClusters(this._graph)
      }
    })
  }

  // — Public API (called from Stimulus controller) —

  toggleIdeas() {
    this._showIdeas = !this._showIdeas
    this._nodeMap.clear()
    const data = this._showIdeas ? this._data : filteredData(this._data)
    this._connectedMap = buildConnectedMap(data)
    this._graph.graphData(data)
  }

  toggleDag() {
    if (this._dagMode === "td") {
      this._dagMode = ""
      this._graph.dagMode(null)
    } else {
      this._dagMode = "td"
      this._graph.dagMode("td")
    }
    this._graph.numDimensions(3)
    return this._dagMode
  }

  zoomIn() {
    if (!this._graph) return
    const cam = this._graph.camera()
    this._graph.cameraPosition(
      { x: cam.position.x * 0.7, y: cam.position.y * 0.7, z: cam.position.z * 0.7 },
      null, 400
    )
  }

  zoomOut() {
    if (!this._graph) return
    const cam = this._graph.camera()
    this._graph.cameraPosition(
      { x: cam.position.x * 1.4, y: cam.position.y * 1.4, z: cam.position.z * 1.4 },
      null, 400
    )
  }

  fitAll() {
    if (!this._graph) return
    this._graph.zoomToFit(600, 40)
  }

  search(term) {
    this._searchTerm = (term || "").toLowerCase().trim()
    this._applyHighlights()
  }

  get showIdeas() { return this._showIdeas }
  get dagMode() { return this._dagMode }

  destroy() {
    if (this._stopAnimation) this._stopAnimation()
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this._subscription) this._subscription.unsubscribe()
    if (this._graph) this._graph._destructor && this._graph._destructor()
  }
}
