import * as THREE from 'three'
import { ConvexGeometry } from 'three/examples/jsm/geometries/ConvexGeometry.js'

const HULL_MESHES = []
let rebuildTimer = null

/**
 * Build convex hull meshes for each root topology group.
 * Requires nodes to have `root_id` and `root_color` fields.
 * Only groups with 4+ positioned nodes produce a hull.
 */
export function buildClusterHulls(graph) {
  const scene = graph.scene()
  clearHulls(scene)

  const nodes = graph.graphData().nodes

  // Group nodes by root_id
  const groups = new Map()
  for (const n of nodes) {
    if (!n.root_id) continue
    if (n.x === undefined) continue // not yet positioned
    if (!groups.has(n.root_id)) groups.set(n.root_id, { color: n.root_color || '#e8b04a', nodes: [] })
    groups.get(n.root_id).nodes.push(n)
  }

  for (const [, group] of groups) {
    if (group.nodes.length < 4) continue

    const points = group.nodes.map(n => new THREE.Vector3(n.x, n.y, n.z))

    try {
      const geo = new ConvexGeometry(points)
      const mat = new THREE.MeshBasicMaterial({
        color: new THREE.Color(group.color),
        transparent: true,
        opacity: 0.06,
        side: THREE.DoubleSide,
        depthWrite: false,
      })
      const mesh = new THREE.Mesh(geo, mat)
      mesh.userData.__clusterHull = true
      scene.add(mesh)
      HULL_MESHES.push(mesh)
    } catch {
      // ConvexGeometry can throw for degenerate point sets — skip
    }
  }
}

/**
 * Remove all existing hull meshes from the scene.
 */
function clearHulls(scene) {
  for (const mesh of HULL_MESHES) {
    scene.remove(mesh)
    mesh.geometry.dispose()
    mesh.material.dispose()
  }
  HULL_MESHES.length = 0
}

/**
 * Debounced cluster rebuild — call after data changes or engine stops.
 */
export function debouncedRebuildClusters(graph, delay = 500) {
  if (rebuildTimer) clearTimeout(rebuildTimer)
  rebuildTimer = setTimeout(() => buildClusterHulls(graph), delay)
}
