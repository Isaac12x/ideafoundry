// Lazy bundle for privacy_gaze / privacy_gaze_calibrate controllers: mediapipe FaceLandmarker + camera loop.
// Everything is served locally (wasm + model are copied next to this file by esbuild.config.mjs).
import { FaceLandmarker } from "@mediapipe/tasks-vision"
import { extractFeatures } from "./gaze_state.js"

export * from "./gaze_state.js"

const FRAME_MS = 80 // ~12fps

// Opens the camera and calls onSample(features|null, now) ~12x/s. Pauses (camera released) while the tab is hidden.
// Fails via onError(err); stop() releases everything.
export async function startGazeSession({ assets, video, onSample, onError }) {
  let stream, landmarker, raf, last = 0, stopped = false
  const v = video || Object.assign(document.createElement("video"), { muted: true, playsInline: true })

  const releaseCamera = () => {
    cancelAnimationFrame(raf)
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
    try { onSample(extractFeatures(landmarker.detectForVideo(v, now)), now) } catch (e) { fail(e) }
  }
  const openCamera = async () => {
    stream = await navigator.mediaDevices.getUserMedia({ video: { width: 320, height: 240, facingMode: "user" }, audio: false })
    if (stopped) return releaseCamera()
    stream.getTracks().forEach((t) => t.addEventListener("ended", () => fail(new Error("camera ended"))))
    v.srcObject = stream
    await v.play()
    raf = requestAnimationFrame(tick)
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
        numFaces: 1,
        outputFaceBlendshapes: true,
        outputFacialTransformationMatrixes: true,
      }
    )
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
