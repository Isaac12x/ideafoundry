import * as THREE from 'three'

/**
 * Apply hover + search highlighting to all nodes and links.
 */
export function applyHighlights(graph, nodeMap, connectedMap, hoveredNode, searchTerm) {
  const nodes = graph.graphData().nodes

  for (const n of nodes) {
    const mat = n.__material
    if (!mat) continue

    if (searchTerm.length > 0) {
      const matches = (n.name || "").toLowerCase().includes(searchTerm)
      if (matches) {
        mat.emissive = new THREE.Color('#fbbf24')
        mat.emissiveIntensity = 1.2
        mat.opacity = 1.0
      } else {
        mat.emissive = new THREE.Color(0x2a1f14)
        mat.emissiveIntensity = 0.05
        mat.opacity = 0.2
      }
    } else if (hoveredNode) {
      const connected = connectedMap.get(hoveredNode.id)
      if (n.id === hoveredNode.id) {
        mat.emissive = n.__baseColor.clone()
        mat.emissiveIntensity = 1.2
        mat.opacity = 1.0
      } else if (connected && connected.has(n.id)) {
        mat.emissive = n.__baseColor.clone()
        mat.emissiveIntensity = 0.9
        mat.opacity = 0.95
      } else {
        mat.emissive = new THREE.Color(0x2a1f14)
        mat.emissiveIntensity = 0.05
        mat.opacity = 0.15
      }
    } else {
      mat.emissive = n.__baseColor.clone()
      mat.emissiveIntensity = n.__baseEmissiveIntensity
      mat.opacity = n.__isTopology ? 0.92 : 0.85
    }
  }

  graph.linkWidth(l => {
    if (!hoveredNode && searchTerm.length === 0) return l.type === 'parent' ? 1.8 : 0.3
    if (searchTerm.length > 0) return l.type === 'parent' ? 1.0 : 0.15
    const src = l.source?.id || l.source
    const tgt = l.target?.id || l.target
    if (src === hoveredNode.id || tgt === hoveredNode.id) return 2.8
    return 0.15
  })
}
