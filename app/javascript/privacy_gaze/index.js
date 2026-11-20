// Lazy bundle for privacy_gaze / privacy_gaze_calibrate controllers: mediapipe FaceLandmarker (fast gaze loop) plus
// @vladmandic/human (~1Hz identity: embedding, anti-spoof, liveness, ears). The camera is opened once and shared.
// Everything is served locally (wasm + models are copied next to this file by esbuild.config.mjs).
import { FaceLandmarker } from "@mediapipe/tasks-vision"
import { Human } from "@vladmandic/human"
import { extractFaces } from "./gaze_state.js"
import { lumaStats, cameraStatus, createFrozenWatch } from "./identity_state.js"

export * from "./gaze_state.js"
export * from "./identity_state.js"

const FRAME_MS = 80 // ~12fps gaze
const HEALTH_MS = 500
const IDENTITY_MS = 1000
const SCHEME = "gaze-model://"

// Human resolves modelBasePath + "faceres.json" and then fetches the weights next to it. Production assets are
// fingerprinted (faceres-<digest>.json, no faceres.bin), so a tfjs load router serves each model from the URL map
// in the privacy-gaze-assets meta instead: assets.human = { faceres: { json, bin }, ... }.
let routed = false
function routeModels(tf, human) {
  if (routed) return
  routed = true
  tf.io.registerLoadRouter((url) => {
    if (typeof url !== "string" || !url.startsWith(SCHEME)) return null
    const name = url.slice(SCHEME.length).replace(/\.json$/, "")
    return {
      async load() {
        const m = human[name]
        if (!m) throw new Error(`unknown model ${name}`)
        const [man, bin] = await Promise.all([fetch(m.json).then((r) => r.json()), fetch(m.bin).then((r) => r.arrayBuffer())])
        return {
          modelTopology: man.modelTopology,
          weightSpecs: man.weightsManifest.flatMap((g) => g.weights),
          weightData: bin, // ponytail: one .bin per model (true for every model we ship)
          format: man.format, generatedBy: man.generatedBy, convertedBy: man.convertedBy, signature: man.signature,
        }
      },
    }
  })
}

const SKIP_NONE = { skipFrames: 0, skipTime: 0 } // 1Hz calls: never reuse a cached (older) frame result

// Loads the Human models. detect(video, descriptors) -> { faces: [{ similarity, real, live, center, embedding }], body }.
export async function createIdentity(assets) {
  const config = {
    backend: "webgl", wasmPath: "/", modelBasePath: SCHEME, // wasmPath: never the default jsdelivr CDN (wasm backend unused)
     cacheModels: false, debug: false, async: true, warmup: "none",
    cacheSensitivity: 0, skipAllowed: false,
    filter: { enabled: false }, gesture: { enabled: false }, hand: { enabled: false }, object: { enabled: false }, segmentation: { enabled: false },
    face: {
      enabled: true,
      detector: { rotation: true, maxDetected: 4, minConfidence: 0.3, ...SKIP_NONE },
      mesh: { enabled: true }, iris: { enabled: false }, emotion: { enabled: false }, attention: { enabled: false },
      description: { enabled: true, minConfidence: 0.1, ...SKIP_NONE },
      antispoof: { enabled: true, ...SKIP_NONE }, liveness: { enabled: true, ...SKIP_NONE },
    },
    body: { enabled: true, modelPath: "movenet-lightning.json", maxDetected: 3, minConfidence: 0.2, ...SKIP_NONE },
  }
  const human = new Human(config)
  routeModels(human.tf, assets.human)
  try { await human.load() } catch (e) { human.config.backend = "cpu"; await human.load() } // still local; webgl may be missing
  await human.init?.()
  return {
    async detect(video, descriptors = []) {
      const r = await human.detect(video)
      const faces = (r.face || []).map((f) => ({
        embedding: f.embedding,
        similarity: f.embedding && descriptors.length ? Math.max(...descriptors.map((d) => human.match.similarity(f.embedding, d))) : 0,
        real: f.real ?? 0,
        live: f.live ?? 0,
        box: { x: f.boxRaw[0], y: f.boxRaw[1], w: f.boxRaw[2], h: f.boxRaw[3] },
        center: { x: f.boxRaw[0] + f.boxRaw[2] / 2, y: f.boxRaw[1] + f.boxRaw[3] / 2 },
      }))
      // ear positions are normalized 0..1 of the frame (positionRaw), so they can be tied to a face box
      const ear = (b, n) => {
        const k = b.keypoints?.find((p) => p.part === n)
        const p = k?.positionRaw || (k && [k.position[0] / video.videoWidth, k.position[1] / video.videoHeight])
        return k && p ? { score: k.score ?? 0, x: p[0], y: p[1] } : null
      }
      const bodies = (r.body || []).map((b) => ({ leftEar: ear(b, "leftEar"), rightEar: ear(b, "rightEar") }))
      return { faces, bodies }
    },
  }
}

// Opens the camera and calls onSample(features0|null, now, allFaces) ~12x/s, onHealth(status) ~2x/s and, when
// `identity` is set, onIdentity(result, now) every identityMs (1s) (getDescriptors() supplies the enrolled embeddings).
// Pauses (camera released) while the tab is hidden. Fails via onError(err); stop() releases everything.
export async function startGazeSession({ assets, video, onSample, onError, onHealth, onIdentity, identity = false, identityMs = IDENTITY_MS, getDescriptors = () => [] }) {
  let stream, landmarker, human, raf, healthTimer, idTimer, last = 0, stopped = false, busy = false
  const v = video || Object.assign(document.createElement("video"), { muted: true, playsInline: true })
  const canvas = Object.assign(document.createElement("canvas"), { width: 16, height: 12 })
  const ctx = canvas.getContext("2d", { willReadFrequently: true })
  const frozen = createFrozenWatch()

  const releaseCamera = () => {
    cancelAnimationFrame(raf)
    clearInterval(healthTimer)
    clearInterval(idTimer)
    stream?.getTracks().forEach((t) => t.stop())
    stream = null
    v.srcObject = null
  }
  const fail = (e) => { if (!stopped) { releaseCamera(); onError(e) } }

  const tick = (now) => {
    if (stopped || !stream) return
    raf = requestAnimationFrame(tick)
    if (now - last < FRAME_MS || v.readyState < 2) return
    last = now
    try {
      const faces = extractFaces(landmarker.detectForVideo(v, now))
      onSample(faces[0] ?? null, now, faces)
    } catch (e) { fail(e) }
  }
  const health = () => {
    if (!stream || !onHealth) return
    const now = performance.now()
    let stats = null
    if (v.readyState >= 2) { try { ctx.drawImage(v, 0, 0, 16, 12); stats = lumaStats(ctx.getImageData(0, 0, 16, 12).data) } catch {} }
    const track = stream.getVideoTracks()[0]
    onHealth(cameraStatus({ stats, frozen: frozen(v.currentTime, now), muted: !track || track.muted || track.readyState !== "live" }))
  }
  const identify = async () => {
    if (busy || !stream || v.readyState < 2 || document.hidden) return
    busy = true
    try {
      const r = await human.detect(v, getDescriptors())
      if (!stopped && stream) onIdentity(r, performance.now())
    } catch (e) { fail(e) } finally { busy = false }
  }
  const openCamera = async () => {
    stream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 480, facingMode: "user" }, audio: false })
    if (stopped) return releaseCamera()
    stream.getTracks().forEach((t) => t.addEventListener("ended", () => fail(new Error("camera ended"))))
    v.srcObject = stream
    await v.play()
    raf = requestAnimationFrame(tick)
    healthTimer = setInterval(health, HEALTH_MS)
    if (identity) idTimer = setInterval(identify, identityMs)
  }
  const onVisibility = () => {
    if (document.hidden) releaseCamera()
    else if (!stream && !stopped) openCamera().catch(fail)
  }

  try {
    landmarker = await FaceLandmarker.createFromOptions(
      { wasmLoaderPath: assets.wasmLoader, wasmBinaryPath: assets.wasm },
      {
        baseOptions: { modelAssetPath: assets.model, delegate: "CPU" },
        runningMode: "VIDEO",
        numFaces: 2,
        outputFaceBlendshapes: true,
        outputFacialTransformationMatrixes: true,
      }
    )
    if (identity) human = await createIdentity(assets)
    if (!document.hidden) await openCamera()
  } catch (e) {
    fail(e)
    landmarker?.close()
    return { stop() {} }
  }
  document.addEventListener("visibilitychange", onVisibility)
  return {
    stop() {
      stopped = true
      document.removeEventListener("visibilitychange", onVisibility)
      releaseCamera()
      landmarker?.close()
    },
  }
}
