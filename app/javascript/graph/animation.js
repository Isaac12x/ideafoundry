/**
 * Start the RAF animation loop: camera-following point light + emissive pulse.
 * Returns a stop() function.
 */
export function startAnimationLoop(graph, pointLight, nodeMap, getState) {
  const startTime = performance.now()
  let id = null

  const tick = () => {
    id = requestAnimationFrame(tick)
    const elapsed = (performance.now() - startTime) / 1000

    // Camera-following point light
    if (pointLight && graph) {
      const cam = graph.camera()
      pointLight.position.copy(cam.position)
    }

    // Subtle emissive pulse on topology nodes (idle only)
    const { hoveredNode, searchTerm } = getState()
    if (!hoveredNode && !searchTerm) {
      for (const [, n] of nodeMap) {
        if (n.__isTopology && n.__material) {
          const pulse = Math.sin(elapsed * 1.5 + (n.__baseColor?.r || 0) * 10) * 0.1
          n.__material.emissiveIntensity = n.__baseEmissiveIntensity + pulse
        }
      }
    }
  }
  tick()

  return () => { if (id) cancelAnimationFrame(id) }
}
