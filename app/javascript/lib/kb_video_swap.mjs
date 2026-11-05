// Instant video switching in the KB. Clicking a video in the tree re-points the player that is already on screen
// (the versioned serve URL is on the link: the very URL the frame's own player would use), instead of waiting for the frame round trip to build a new <video> and rebuffer.
// When the frame for that same file arrives it keeps the live element (adoptLiveVideo) and only the surroundings change.
export const PLAYER = "#kb-content video.kb-video-player"
const KEY = "kbSwapKey"

export const swapKey = (src, rel) => `${src}:${rel}`

// Returns an undo function when a resume controller took the swap (the player is now on the new file), else null:
// a video nobody handles (the media editor's) keeps its old file, so the caller must stop it itself.
export function swapTo(video, { url, key }) {
  const detail = { url, key, undo: null }
  video.dispatchEvent(new CustomEvent("kb-video:swap", { detail }))
  return detail.undo
}

export function markSwapped(video, key) { video.dataset[KEY] = key }

// Turbo before-frame-render handler: if the incoming #kb-content frame shows the file we swapped to, carry the live <video> over.
// Anything else (other frames, no matching video) keeps Turbo's own render; when it applies we only move the element
// into the incoming tree first and still run Turbo's render, so script activation, autofocus and scroll stay.
export function adoptRender(event) {
  const frame = event.target
  const next = event.detail?.newFrame
  if (frame?.id !== "kb-content" || !next) return
  const live = frame.querySelector("video.kb-video-player")
  const incoming = next.querySelector("video.kb-video-player")
  if (!live || !incoming || !live.dataset[KEY] || live.dataset[KEY] !== incoming.dataset.kbResumeKeyValue) return
  const turboRender = event.detail.render
  event.detail.render = (current, incomingFrame) => {
    adoptLiveVideo(live, incomingFrame.querySelector("video.kb-video-player") || incoming)
    turboRender(current, incomingFrame)
  }
}

// Same element, new surroundings: take the fresh data-* (controller values, targets, actions) and captions,
// then put the live element where the new one was. Removal and re-insertion happen in one task, so playback never pauses.
export function adoptLiveVideo(live, incoming) {
  for (const { name, value } of Array.from(incoming.attributes)) if (name.startsWith("data-") && name !== `data-kb-swap-key`) live.setAttribute(name, value)
  live.querySelectorAll("track").forEach((track) => track.remove())
  incoming.querySelectorAll("track").forEach((track) => live.append(track))
  incoming.replaceWith(live)
}

// Hovering a video link starts reading its header/index (a faststart-less mp4 keeps its index at the end, which
// costs extra round trips). Chrome shares the buffered data with the player that opens the same versioned URL.
export function warm(state, link) {
  const url = link?.dataset.kbVideo
  if (!url || state.url === url) return
  state.url = url
  state.video ||= Object.assign(document.createElement("video"), { muted: true, preload: "metadata" })
  state.video.src = url
}

export function unwarm(state) {
  state.video?.removeAttribute("src")
  state.video?.load()
  state.video = state.url = null
}
