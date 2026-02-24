/**
 * Build adjacency map: nodeId → Set<connectedNodeIds>
 */
export function buildConnectedMap(data) {
  const map = new Map()
  for (const l of data.links || []) {
    const src = l.source?.id || l.source
    const tgt = l.target?.id || l.target
    if (!map.has(src)) map.set(src, new Set())
    if (!map.has(tgt)) map.set(tgt, new Set())
    map.get(src).add(tgt)
    map.get(tgt).add(src)
  }
  return map
}

/**
 * Filter out idea nodes/links, returning topology-only data.
 */
export function filteredData(data) {
  const nodes = data.nodes.filter(n => n.type !== 'idea')
  const nodeIds = new Set(nodes.map(n => n.id))
  const links = data.links.filter(l =>
    nodeIds.has(l.source?.id || l.source) && nodeIds.has(l.target?.id || l.target)
  )
  return { nodes, links }
}

/**
 * Escape HTML entities for safe tooltip rendering.
 */
export function escapeHtml(str) {
  const div = document.createElement('div')
  div.textContent = str
  return div.innerHTML
}
