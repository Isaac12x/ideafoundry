import { createConsumer } from '@rails/actioncable'

let consumer = null

/**
 * Subscribe to TopologyGraphChannel for real-time graph updates.
 * Calls onPatch(patch) whenever server broadcasts a change.
 */
export function subscribe(onPatch) {
  if (!consumer) consumer = createConsumer()

  return consumer.subscriptions.create("TopologyGraphChannel", {
    received(data) {
      onPatch(data)
    }
  })
}

/**
 * Apply a server-broadcast patch to the graph data.
 * Mutates `data` in place, then calls graph.graphData() to re-render.
 * Returns true if data was changed.
 */
export function applyPatch(data, patch, connectedMapBuilder) {
  let changed = false

  switch (patch.action) {
    case 'node_added': {
      if (!data.nodes.find(n => n.id === patch.node.id)) {
        data.nodes.push(patch.node)
        changed = true
      }
      if (patch.links) {
        for (const link of patch.links) {
          if (!data.links.find(l =>
            (l.source?.id || l.source) === link.source &&
            (l.target?.id || l.target) === link.target
          )) {
            data.links.push(link)
            changed = true
          }
        }
      }
      break
    }
    case 'node_updated': {
      const node = data.nodes.find(n => n.id === patch.node.id)
      if (node) {
        Object.assign(node, patch.node)
        changed = true
      }
      break
    }
    case 'node_removed': {
      const idx = data.nodes.findIndex(n => n.id === patch.node_id)
      if (idx !== -1) {
        data.nodes.splice(idx, 1)
        data.links = data.links.filter(l =>
          (l.source?.id || l.source) !== patch.node_id &&
          (l.target?.id || l.target) !== patch.node_id
        )
        changed = true
      }
      break
    }
    case 'link_added': {
      if (patch.node && !data.nodes.find(n => n.id === patch.node.id)) {
        data.nodes.push(patch.node)
      }
      if (patch.link && !data.links.find(l =>
        (l.source?.id || l.source) === patch.link.source &&
        (l.target?.id || l.target) === patch.link.target
      )) {
        data.links.push(patch.link)
        changed = true
      }
      break
    }
    case 'link_removed': {
      const before = data.links.length
      data.links = data.links.filter(l =>
        !((l.source?.id || l.source) === patch.link_source &&
          (l.target?.id || l.target) === patch.link_target)
      )
      if (data.links.length !== before) changed = true

      // Remove orphan idea nodes (no remaining links)
      if (patch.orphan_node_id) {
        const orphanIdx = data.nodes.findIndex(n => n.id === patch.orphan_node_id)
        if (orphanIdx !== -1) {
          const hasLinks = data.links.some(l =>
            (l.source?.id || l.source) === patch.orphan_node_id ||
            (l.target?.id || l.target) === patch.orphan_node_id
          )
          if (!hasLinks) {
            data.nodes.splice(orphanIdx, 1)
          }
        }
      }
      break
    }
  }

  if (changed && connectedMapBuilder) {
    connectedMapBuilder(data)
  }
  return changed
}
