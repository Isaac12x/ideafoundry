// Lazy 3D viewer bundle (esbuild -> app/assets/builds/kb_viewers/model.js). kb_model_controller imports it
// only when a model is opened, so three.js never ships with the main page. Mesh formats load through three's
// loaders; STEP/IGES/BREP are tessellated by occt-import-js (wasm, served next to this bundle).
import * as THREE from "three"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { STLLoader } from "three/examples/jsm/loaders/STLLoader.js"
import { OBJLoader } from "three/examples/jsm/loaders/OBJLoader.js"
import { PLYLoader } from "three/examples/jsm/loaders/PLYLoader.js"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import { ThreeMFLoader } from "three/examples/jsm/loaders/3MFLoader.js"
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js"
import { ColladaLoader } from "three/examples/jsm/loaders/ColladaLoader.js"
import occtimportjs from "occt-import-js"

const BREP = { ".step": "ReadStepFile", ".stp": "ReadStepFile", ".iges": "ReadIgesFile", ".igs": "ReadIgesFile", ".brep": "ReadBrepFile" }
// CAD and scan formats are Z-up; glTF/FBX/Collada/OBJ are Y-up.
const Z_UP = new Set([".stl", ".ply", ".3mf", ...Object.keys(BREP)])

export const SUPPORTED = [".stl", ".obj", ".ply", ".gltf", ".glb", ".3mf", ".fbx", ".dae", ...Object.keys(BREP)]

export function formatDims(size) {
  const f = (n) => String(Number(n.toPrecision(4)))
  return `${f(size.x)} × ${f(size.y)} × ${f(size.z)}`
}

const surface = () => new THREE.MeshStandardMaterial({ color: 0x9aa3ad, metalness: 0.1, roughness: 0.6, side: THREE.DoubleSide })

function meshFrom(geometry) {
  if (!geometry.getAttribute("normal")) geometry.computeVertexNormals()
  const material = surface()
  material.vertexColors = !!geometry.getAttribute("color")
  return new THREE.Mesh(geometry, material)
}

function fromOcct(result) {
  if (!result?.success || !result.meshes?.length) throw new Error("The CAD kernel could not read this file.")
  const group = new THREE.Group()
  for (const m of result.meshes) {
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(m.attributes.position.array, 3))
    if (m.attributes.normal) geometry.setAttribute("normal", new THREE.Float32BufferAttribute(m.attributes.normal.array, 3))
    geometry.setIndex(new THREE.BufferAttribute(Uint32Array.from(m.index.array), 1))
    const mesh = meshFrom(geometry)
    if (m.color) mesh.material.color.setRGB(...m.color)
    group.add(mesh)
  }
  return group
}

async function parse(ext, buffer, wasmUrl) {
  const text = () => new TextDecoder().decode(buffer)
  switch (ext) {
    case ".stl": return meshFrom(new STLLoader().parse(buffer))
    case ".ply": {
      const geometry = new PLYLoader().parse(buffer)
      if (geometry.index) return meshFrom(geometry)
      const hasColor = !!geometry.getAttribute("color")
      return new THREE.Points(geometry, new THREE.PointsMaterial({ size: 0.01, vertexColors: hasColor, color: hasColor ? 0xffffff : 0x9aa3ad, sizeAttenuation: true }))
    }
    case ".obj": return new OBJLoader().parse(text())
    case ".gltf": case ".glb": {
      const gltf = await new Promise((resolve, reject) => new GLTFLoader().parse(ext === ".glb" ? buffer : text(), "", resolve, reject))
      return gltf.scene
    }
    case ".3mf": return new ThreeMFLoader().parse(buffer)
    case ".fbx": return new FBXLoader().parse(buffer, "")
    case ".dae": return new ColladaLoader().parse(text(), "").scene
    default: {
      if (!BREP[ext]) throw new Error(`Unsupported 3D format ${ext}.`)
      const occt = await occtimportjs({ locateFile: () => wasmUrl })
      return fromOcct(occt[BREP[ext]](new Uint8Array(buffer), null))
    }
  }
}

function disposeTree(root) {
  root.traverse((node) => {
    node.geometry?.dispose()
    for (const material of [].concat(node.material || [])) {
      for (const value of Object.values(material)) if (value?.isTexture) value.dispose()
      material.dispose()
    }
  })
}

export const MAX_BYTES = 200 * 1024 * 1024 // parsing bigger files freezes the tab

// => { reset(), setWireframe(on), dimsText, dispose() }. Throws a readable Error if the file can't be parsed.
export async function mountModel({ host, url, ext, wasmUrl }) {
  const response = await fetch(url, { credentials: "same-origin" })
  if (!response.ok) throw new Error("Could not download the model.")
  const bytes = Number(response.headers.get("Content-Length"))
  if (bytes > MAX_BYTES) throw new Error(`This model is ${Math.round(bytes / 1048576)} MB; the viewer opens files up to ${MAX_BYTES / 1048576} MB. Download it instead.`)
  let model
  try {
    model = await parse(ext, await response.arrayBuffer(), wasmUrl)
  } catch (error) {
    throw new Error(error?.message ? `Could not read this model: ${error.message}` : "Could not read this model.")
  }

  const dims = new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3()) // model units, own axes
  const pivot = new THREE.Group()
  pivot.add(model)
  if (Z_UP.has(ext)) pivot.rotation.x = -Math.PI / 2
  pivot.updateMatrixWorld(true)
  const box = new THREE.Box3().setFromObject(pivot)
  if (box.isEmpty()) throw new Error("This model has no visible geometry.")
  const sphere = box.getBoundingSphere(new THREE.Sphere())

  const style = getComputedStyle(host)
  const scene = new THREE.Scene()
  scene.add(pivot)
  const grid = new THREE.GridHelper(Math.max(box.max.x - box.min.x, box.max.z - box.min.z, sphere.radius) * 2.5, 20, style.getPropertyValue("--text-muted").trim() || 0x888888, style.getPropertyValue("--border-default").trim() || 0x444444)
  grid.position.set(sphere.center.x, box.min.y, sphere.center.z)
  grid.material.transparent = true
  grid.material.opacity = 0.55
  scene.add(grid)

  const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 1000)
  scene.add(camera) // lights ride the camera so the shaded side always faces the viewer
  camera.add(new THREE.HemisphereLight(0xffffff, 0x555566, 1.2))
  const key = new THREE.DirectionalLight(0xffffff, 1.8)
  key.position.set(1, 2, 1.5)
  camera.add(key)

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
  renderer.domElement.style.cssText = "display:block;width:100%;height:100%"
  host.append(renderer.domElement)

  let frame = 0
  const render = () => { frame = 0; renderer.render(scene, camera) }
  const schedule = () => { frame ||= requestAnimationFrame(render) }

  const controls = new OrbitControls(camera, renderer.domElement)
  controls.listenToKeyEvents(host) // arrow keys pan; host is focusable
  controls.addEventListener("change", schedule)

  const reset = () => {
    const aspect = camera.aspect || 1
    const distance = (sphere.radius / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2))) * 1.05 / Math.min(1, aspect)
    camera.position.copy(sphere.center).addScaledVector(new THREE.Vector3(1, 0.8, 1).normalize(), distance)
    camera.near = distance / 100
    camera.far = distance * 100
    camera.updateProjectionMatrix()
    controls.target.copy(sphere.center)
    controls.update()
    schedule()
  }

  const resize = () => {
    const { clientWidth: width, clientHeight: height } = host
    if (!width || !height) return
    renderer.setSize(width, height, false)
    camera.aspect = width / height
    camera.updateProjectionMatrix()
    schedule()
  }
  const observer = new ResizeObserver(resize)
  observer.observe(host)
  resize()
  reset()

  return {
    dimsText: formatDims(dims),
    reset,
    setWireframe(on) {
      pivot.traverse((node) => { for (const material of [].concat(node.material || [])) material.wireframe = on })
      schedule()
    },
    dispose() {
      cancelAnimationFrame(frame)
      observer.disconnect()
      controls.stopListenToKeyEvents()
      controls.dispose()
      disposeTree(scene)
      renderer.dispose()
      renderer.forceContextLoss()
      renderer.domElement.remove()
    }
  }
}
