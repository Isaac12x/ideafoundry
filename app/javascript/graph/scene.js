import * as THREE from 'three'
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js'

/**
 * Configure renderer tone mapping, fog, and lights on the graph scene.
 */
export function setupScene(graph, settings) {
  const scene = graph.scene()
  const renderer = graph.renderer()

  // Tone mapping
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.1
  renderer.outputColorSpace = THREE.SRGBColorSpace

  // Fog
  const fogDensity = settings.fog_density !== undefined ? settings.fog_density : 0.0018
  scene.fog = new THREE.FogExp2(0x0c0c0f, fogDensity)

  // Ambient
  scene.add(new THREE.AmbientLight(0xaaaacc, 0.5))

  // Key light — warm gold from above
  const keyLight = new THREE.DirectionalLight(0xffe0a8, 1.0)
  keyLight.position.set(50, 100, 30)
  scene.add(keyLight)

  // Fill light — cool blue from below
  const fillLight = new THREE.DirectionalLight(0x88aadd, 0.45)
  fillLight.position.set(-40, -60, -20)
  scene.add(fillLight)

  // Point light following camera (returned for animation loop)
  const pointLight = new THREE.PointLight(0xffeedd, 0.65, 500)
  scene.add(pointLight)

  return pointLight
}

/**
 * Add UnrealBloomPass to the graph's post-processing composer.
 */
export function addBloom(graph, settings) {
  try {
    const composer = graph.postProcessingComposer()
    if (!composer) return

    const el = graph.renderer().domElement
    const bloomStrength = settings.bloom_strength !== undefined ? settings.bloom_strength : 0.8
    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(el.clientWidth, el.clientHeight),
      bloomStrength,
      0.4,
      0.85
    )
    composer.addPass(bloomPass)
  } catch (e) {
    console.warn("Bloom post-processing unavailable:", e.message)
  }
}
