// Pure helpers for the seek-bar frame preview.

// Seconds under a pointer at clientX across the seek bar's rect.
export function timeFromPointer(clientX, rect, duration) {
  if (!(rect.width > 0) || !(duration > 0)) return 0
  const ratio = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1)
  return ratio * duration
}

// Left edge (px) for a box of `width` centred on `center`, kept inside [0, bound].
export function clampLeft(center, width, bound) {
  return Math.max(0, Math.min(center - width / 2, bound - width))
}

// Frames within one bucket share a cached thumbnail; ~150 buckets per video, at least 0.5s wide.
export function bucketStep(duration) { return Math.max(0.5, duration / 150) }
export function bucketTime(time, step) { return Math.floor(time / step) * step }
