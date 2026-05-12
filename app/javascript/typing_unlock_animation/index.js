import * as THREE from "three"

const clamp01 = (value) => Math.max(0, Math.min(1, value))
const easeOutQuint = (value) => 1 - Math.pow(1 - clamp01(value), 5)
const easeInOut = (value) => {
  const t = clamp01(value)
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
}

class ShackleCurve extends THREE.Curve {
  getPoint(t) {
    const u = clamp01(t)

    if (u < 0.28) {
      return new THREE.Vector3(0, (u / 0.28) * 0.72, 0)
    }

    if (u < 0.72) {
      const local = (u - 0.28) / 0.44
      const angle = Math.PI - local * Math.PI

      return new THREE.Vector3(
        0.52 + Math.cos(angle) * 0.52,
        0.72 + Math.sin(angle) * 0.48,
        0
      )
    }

    return new THREE.Vector3(1.04, 0.72 - ((u - 0.72) / 0.28) * 0.72, 0)
  }
}

function roundedRectShape(width, height, radius) {
  const shape = new THREE.Shape()
  const x = -width / 2
  const y = -height / 2

  shape.moveTo(x + radius, y)
  shape.lineTo(x + width - radius, y)
  shape.quadraticCurveTo(x + width, y, x + width, y + radius)
  shape.lineTo(x + width, y + height - radius)
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  shape.lineTo(x + radius, y + height)
  shape.quadraticCurveTo(x, y + height, x, y + height - radius)
  shape.lineTo(x, y + radius)
  shape.quadraticCurveTo(x, y, x + radius, y)

  return shape
}

function disposeMaterial(material) {
  if (Array.isArray(material)) {
    material.forEach(disposeMaterial)
    return
  }

  material?.dispose()
}

export class TypingUnlockAnimation {
  constructor(container, options = {}) {
    this.container = container
    this.result = options.result || "matched"
    this.isMatched = this.result === "matched"
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.destroyed = false
    this.duration = this.isMatched ? 1350 : 760
    this.startTime = performance.now()

    this.scene = new THREE.Scene()
    this.camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100)
    this.camera.position.set(0, 0.12, 5.7)
    this.camera.lookAt(0, 0.12, 0)

    this.renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: true
    })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
    this.renderer.outputColorSpace = THREE.SRGBColorSpace
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping
    this.renderer.toneMappingExposure = 1.05

    this.container.replaceChildren(this.renderer.domElement)

    this.buildScene()
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.container)
    this.resize()

    if (this.reducedMotion) {
      this.renderFrame(this.startTime + this.duration)
    } else {
      this.frameRequest = requestAnimationFrame((time) => this.animate(time))
    }
  }

  buildScene() {
    this.lockGroup = new THREE.Group()
    this.scene.add(this.lockGroup)

    const hemisphere = new THREE.HemisphereLight(0xfff0cf, 0x4a3340, 2.8)
    const keyLight = new THREE.DirectionalLight(0xffffff, 3.5)
    const rimLight = new THREE.DirectionalLight(0xa4d1ff, 1.7)
    const warmPin = new THREE.PointLight(0xffcf7a, 1.9, 8)

    keyLight.position.set(2.6, 3.2, 4.6)
    rimLight.position.set(-3.6, 1.8, 2.4)
    warmPin.position.set(0, -1.8, 3.2)

    this.scene.add(hemisphere, keyLight, rimLight, warmPin)

    this.bodyGroup = new THREE.Group()
    this.bodyGroup.position.set(0, -0.46, 0)
    this.lockGroup.add(this.bodyGroup)

    const bodyGeometry = new THREE.ExtrudeGeometry(roundedRectShape(1.58, 1.04, 0.14), {
      depth: 0.42,
      bevelEnabled: true,
      bevelSegments: 8,
      bevelSize: 0.035,
      bevelThickness: 0.045
    })
    bodyGeometry.center()

    const bodyMaterial = new THREE.MeshStandardMaterial({
      color: 0xd59b42,
      metalness: 0.82,
      roughness: 0.28
    })
    const body = new THREE.Mesh(bodyGeometry, bodyMaterial)
    body.rotation.x = -0.08
    this.bodyGroup.add(body)

    const faceMaterial = new THREE.MeshBasicMaterial({
      color: 0xffefd0,
      transparent: true,
      opacity: 0.32,
      depthWrite: false
    })
    const face = new THREE.Mesh(new THREE.PlaneGeometry(1.16, 0.42), faceMaterial)
    face.position.set(-0.06, 0.12, 0.235)
    this.bodyGroup.add(face)

    const keyholeMaterial = new THREE.MeshBasicMaterial({ color: 0x281f24 })
    const keyholeTop = new THREE.Mesh(new THREE.CircleGeometry(0.095, 32), keyholeMaterial)
    const keyholeStem = new THREE.Mesh(new THREE.PlaneGeometry(0.08, 0.31), keyholeMaterial)
    keyholeTop.position.set(0, -0.08, 0.252)
    keyholeStem.position.set(0, -0.245, 0.254)
    this.bodyGroup.add(keyholeTop, keyholeStem)

    const socketMaterial = new THREE.MeshStandardMaterial({
      color: 0x9b6a35,
      metalness: 0.8,
      roughness: 0.38
    })
    const socketGeometry = new THREE.CylinderGeometry(0.13, 0.13, 0.16, 28)
    for (const x of [-0.52, 0.52]) {
      const socket = new THREE.Mesh(socketGeometry, socketMaterial)
      socket.rotation.x = Math.PI / 2
      socket.position.set(x, 0.17, 0.23)
      this.bodyGroup.add(socket)
    }

    this.shacklePivot = new THREE.Group()
    this.shacklePivot.position.set(-0.52, -0.13, 0.02)
    this.lockGroup.add(this.shacklePivot)

    const shackleMaterial = new THREE.MeshStandardMaterial({
      color: 0xb9c3c7,
      metalness: 0.92,
      roughness: 0.18
    })
    const shackle = new THREE.Mesh(new THREE.TubeGeometry(new ShackleCurve(), 76, 0.075, 20, false), shackleMaterial)
    this.shacklePivot.add(shackle)

    const glowMaterial = new THREE.MeshBasicMaterial({
      color: this.isMatched ? 0x54b56f : 0xb54856,
      transparent: true,
      opacity: 0.18,
      depthWrite: false
    })
    this.glow = new THREE.Mesh(new THREE.CircleGeometry(1.28, 64), glowMaterial)
    this.glow.position.set(0, -0.12, -0.18)
    this.lockGroup.add(this.glow)
  }

  resize() {
    if (this.destroyed) return

    const rect = this.container.getBoundingClientRect()
    const width = Math.max(1, Math.round(rect.width || 230))
    const height = Math.max(1, Math.round(rect.height || 160))

    this.renderer.setSize(width, height, false)
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    this.renderer.render(this.scene, this.camera)
  }

  animate(time) {
    if (this.destroyed) return

    this.renderFrame(time)

    if (time - this.startTime < this.duration) {
      this.frameRequest = requestAnimationFrame((nextTime) => this.animate(nextTime))
    }
  }

  renderFrame(time) {
    const rawProgress = this.reducedMotion ? 1 : clamp01((time - this.startTime) / this.duration)

    if (this.isMatched) {
      const release = easeOutQuint((rawProgress - 0.16) / 0.58)
      const settle = easeInOut((rawProgress - 0.72) / 0.28)

      this.shacklePivot.position.y = -0.13 + release * 0.34 - settle * 0.04
      this.shacklePivot.rotation.z = -release * 0.48 + settle * 0.06
      this.bodyGroup.rotation.z = Math.sin(rawProgress * Math.PI) * 0.035
      this.bodyGroup.position.y = -0.46 - Math.sin(rawProgress * Math.PI) * 0.025
      this.glow.scale.setScalar(1 + release * 0.42)
      this.glow.material.opacity = 0.1 + release * 0.16
    } else {
      const shake = Math.sin(rawProgress * Math.PI * 10) * (1 - rawProgress) * 0.06

      this.lockGroup.position.x = shake
      this.lockGroup.rotation.z = shake * 0.18
      this.glow.scale.setScalar(1 + Math.sin(rawProgress * Math.PI) * 0.12)
      this.glow.material.opacity = 0.14
    }

    this.lockGroup.rotation.y = -0.12 + Math.sin(rawProgress * Math.PI) * 0.08
    this.renderer.render(this.scene, this.camera)
  }

  destroy() {
    this.destroyed = true

    if (this.frameRequest) cancelAnimationFrame(this.frameRequest)
    this.resizeObserver?.disconnect()

    this.scene.traverse((object) => {
      object.geometry?.dispose()
      disposeMaterial(object.material)
    })

    this.renderer.dispose()
    this.renderer.domElement.remove()
  }
}
