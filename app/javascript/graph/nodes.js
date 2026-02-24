import * as THREE from 'three'
import SpriteText from 'three-spritetext'

/**
 * Create a Three.js Group for a graph node.
 * Registers __material, __isTopology, __baseEmissiveIntensity, __baseColor on the node.
 */
export function makeNodeObject(node, nodeMap, settings) {
  const group = new THREE.Group()

  const isTopology = node.type !== 'idea'
  const baseColor = new THREE.Color(node.color || '#e8b04a')
  const nodeVal = node.val || 3
  const size = isTopology ? Math.max(3, Math.min(12, nodeVal * 0.9 + 2)) : 2.2

  // Geometry — faceted icosahedron for topology, octahedron for ideas
  const geometry = isTopology
    ? new THREE.IcosahedronGeometry(size, 0)
    : new THREE.OctahedronGeometry(size, 0)

  // PBR material with emissive glow
  const material = new THREE.MeshStandardMaterial({
    color: baseColor,
    emissive: baseColor,
    emissiveIntensity: isTopology ? 0.8 : 0.6,
    metalness: isTopology ? 0.6 : 0.25,
    roughness: isTopology ? 0.2 : 0.55,
    transparent: true,
    opacity: isTopology ? 0.95 : 0.9,
  })

  group.add(new THREE.Mesh(geometry, material))

  // Outer glow shell (topology only)
  if (isTopology) {
    const glowGeo = new THREE.IcosahedronGeometry(size * 1.35, 1)
    const glowMat = new THREE.MeshBasicMaterial({
      color: baseColor,
      transparent: true,
      opacity: 0.08,
      side: THREE.BackSide,
    })
    group.add(new THREE.Mesh(glowGeo, glowMat))
  }

  // SpriteText label — topology only
  if (isTopology) {
    const sprite = new SpriteText(node.name || "")
    sprite.color = '#f5f2ec'
    sprite.textHeight = 3.2
    sprite.fontFace = "Outfit, sans-serif"
    sprite.fontWeight = "600"
    sprite.backgroundColor = "rgba(12,12,15,0.7)"
    sprite.padding = 1.8
    sprite.borderRadius = 3
    sprite.borderWidth = 0.3
    sprite.borderColor = `rgba(${Math.round(baseColor.r*255)},${Math.round(baseColor.g*255)},${Math.round(baseColor.b*255)},0.3)`
    sprite.position.y = size + 5
    group.add(sprite)
  }

  // Store refs for material manipulation
  node.__material = material
  node.__isTopology = isTopology
  node.__baseEmissiveIntensity = isTopology ? 0.8 : 0.6
  node.__baseColor = baseColor
  nodeMap.set(node.id, node)

  return group
}
